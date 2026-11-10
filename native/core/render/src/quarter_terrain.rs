//! Rasterized spatial terrain patches in the existing indexed regional atlas.
//! Corner heights are quarter levels; vertical faces join independent plateaus.

use crate::{Builder, City, Draw, Rect, sprites::Sprite};

pub const FIRST_IMAGE: u64 = 1_400_000_000;
const MASKS: [u8; 16] = [0, 9, 3, 6, 12, 11, 7, 14, 13, 1, 2, 4, 8, 15, 0, 0];
const EDGES: [[usize; 2]; 4] = [[0, 1], [1, 2], [2, 3], [3, 0]];
const POINTS: [[f32; 2]; 4] = [[-0.5, -0.5], [0.5, -0.5], [0.5, 0.5], [-0.5, 0.5]];

impl City {
    pub(super) fn quarter_corners(&self, index: usize) -> [i16; 4] {
        self.quarter.get(index).copied().unwrap_or_else(|| {
            let mask = MASKS[(self.terrain[index] & 15) as usize];
            std::array::from_fn(|k| (self.land(index) * 4 + if mask & (1 << k) != 0 { 4 } else { 0 }) as i16)
        })
    }
}

impl Builder {
    pub(super) fn quarter_corners(&self, index: usize) -> [i16; 4] {
        self.city.quarter_corners(index)
    }

    pub(super) fn quarter_ground(
        &mut self,
        draws: &mut Vec<Draw>,
        sprite: i32,
        sx: i32,
        baseline: i32,
        index: usize,
    ) -> Result<(), String> {
        if !self.terrain_models || (self.city.wet(index) && self.city.quarter.is_empty()) || self.city.terrain[index] == 0x3e {
            return self.add(draws, sprite, false, sx, baseline).map(|_| ());
        }
        // The spatial patch already contains the water/land height difference.
        // Its local origin is land, even when classic sprites use a water anchor
        // or a hidden-water view preserves a structure's object altitude.
        let baseline = baseline + (self.city.object(index) - self.city.land(index)) * self.config.step();
        let edge = self.city.edge;
        let x = index as i32 / edge;
        let y = index as i32 % edge;
        let ground = self.city.land(index) * 4;
        let top = self.quarter_corners(index);
        let mut key: Vec<i16> = top.iter().map(|q| *q - ground as i16).collect();
        for (side, (dx, dy)) in [(0, -1), (1, 0), (0, 1), (-1, 0)].into_iter().enumerate() {
            let neighbor = if x + dx >= 0 && y + dy >= 0 && x + dx < edge && y + dy < edge {
                self.quarter_corners(self.city.index(x + dx, y + dy))
            } else {
                [0; 4]
            };
            let [a, b] = EDGES[(side + 2) % 4];
            key.extend([neighbor[b] - ground as i16, neighbor[a] - ground as i16]);
        }
        key.push(if self.city.wet(index) {
            (self.city.water(index) * 4 - ground) as i16
        } else {
            i16::MIN
        });
        let (image, padding) = if let Some(value) = self.quarter_ground_cache.get(&key) {
            *value
        } else {
            let flat = self.sprites.get(self.config.base() + 256, false)?;
            let side = self.sprites.get(self.config.base() + 269, false)?;
            let water = self.sprites.get(self.config.base() + 270, false)?;
            let (raster, padding) = raster(
                &key,
                &self.sprites.images[&flat],
                &self.sprites.images[&side],
                &self.sprites.images[&water],
                self.config.divisor(),
            );
            let image = FIRST_IMAGE + self.quarter_ground_cache.len() as u64 * 2;
            self.sprite_limit.0 = self.sprite_limit.0.max(raster.w);
            self.sprite_limit.1 = self.sprite_limit.1.max(raster.h);
            self.sprites.images.insert(image, raster);
            self.quarter_ground_cache.insert(key, (image, padding));
            (image, padding)
        };
        let pixels = &self.sprites.images[&image];
        let mut draw = Draw::new(image, Rect::new(sx, baseline - pixels.h + padding, pixels.w, pixels.h));
        draw.sprite = sprite;
        draws.push(draw);
        Ok(())
    }

    pub(super) fn quarter_objects(&mut self, index: usize, draws: &mut [Draw]) -> Result<(), String> {
        if self.city.quarter.is_empty() {
            return Ok(());
        }
        let q = self.quarter_corners(index);
        let fraction = i32::from(*q.iter().min().unwrap()) - self.city.land(index) * 4;
        let legacy_raised = if self.city.terrain[index] == 13 { self.config.step() } else { 0 };
        let shift = if self.city.wet(index) {
            0
        } else {
            (fraction * 3 + self.config.divisor() / 2) / self.config.divisor() - legacy_raised
        };
        let model = self.quarter_networks.get(index).copied().unwrap_or(0);
        let building = i32::from(self.city.buildings[index]);
        for draw in draws {
            let original = crate::nature::original(draw.sprite).rem_euclid(500);
            if model != 0 && original == building && !draw.moving && !draw.shadow {
                let key = self.sprites.get(model, draw.flip)?;
                let image = &self.sprites.images[&key];
                draw.rect.y += draw.rect.h - image.h + legacy_raised;
                draw.rect.w = image.w;
                draw.rect.h = image.h;
                draw.image = key;
            } else if !(256..=290).contains(&original) && !draw.shadow {
                draw.rect.y -= shift;
            }
        }
        Ok(())
    }
}

type Point = [f32; 3];
fn project(p: Point) -> [f32; 2] {
    [16.0 * (p[0] - p[1]), 8.0 * (p[0] + p[1]) - p[2]]
}
fn vertex(k: usize, q: i16) -> Point {
    [POINTS[k][0], POINTS[k][1], f32::from(q) * 3.0]
}

fn raster(key: &[i16], top: &Sprite, side: &Sprite, water: &Sprite, divisor: i32) -> (Sprite, i32) {
    let corners: [Point; 4] = std::array::from_fn(|k| vertex(k, key[k]));
    let mut faces = vec![(corners, 0_u8)];
    if key[12] != i16::MIN {
        faces.push((std::array::from_fn(|k| vertex(k, key[12])), 2));
    }
    for (s, [a, b]) in EDGES.into_iter().enumerate() {
        let lower_a = key[4 + s * 2].min(key[a]);
        let lower_b = key[5 + s * 2].min(key[b]);
        if lower_a < key[a] || lower_b < key[b] {
            faces.push(([corners[a], corners[b], vertex(b, lower_b), vertex(a, lower_a)], 1));
        }
    }
    let low = faces
        .iter()
        .flat_map(|(f, _)| f.iter())
        .map(|p| project(*p)[1])
        .fold(-8.0_f32, f32::min);
    let high = faces
        .iter()
        .flat_map(|(f, _)| f.iter())
        .map(|p| project(*p)[1])
        .fold(8.0_f32, f32::max);
    let padding = (high - 8.0).max(0.0).ceil() as i32;
    let height = 9 + padding + (-low).ceil() as i32;
    let mut rgba = vec![0_u8; (32 * height * 4) as usize];
    let mut depth = vec![f32::NEG_INFINITY; (32 * height) as usize];
    let origin = [16.0, (height - 9 - padding) as f32];
    for (face, material) in faces {
        for tri in [[0, 1, 2], [0, 2, 3]] {
            triangle(
                [face[tri[0]], face[tri[1]], face[tri[2]]],
                material != 1,
                if material == 2 { water } else { top },
                side,
                &key[..4],
                if material == 2 || key[12] == i16::MIN {
                    f32::NEG_INFINITY
                } else {
                    f32::from(key[12]) * 3.0
                },
                origin,
                height,
                &mut rgba,
                &mut depth,
            );
        }
    }
    let width = 32 / divisor;
    let small_height = (height + divisor - 1) / divisor;
    let offset = small_height * divisor - height;
    let mut result = Sprite {
        w: width,
        h: small_height,
        rgba: vec![0; (width * small_height * 4) as usize],
        la: vec![0; (width * small_height * 2) as usize],
    };
    for y in 0..small_height {
        for x in 0..width {
            let mut best = f32::INFINITY;
            for sy in 0..divisor {
                for sx in 0..divisor {
                    let row = y * divisor + sy - offset;
                    if row < 0 || row >= height {
                        continue;
                    }
                    let source = ((row * 32 + x * divisor + sx) * 4) as usize;
                    let distance = (sx as f32 + 0.5 - divisor as f32 * 0.5).powi(2) + (sy as f32 + 0.5 - divisor as f32 * 0.5).powi(2);
                    if rgba[source + 3] != 0 && distance < best {
                        best = distance;
                        let at = (y * width + x) as usize;
                        result.rgba[at * 4..at * 4 + 4].copy_from_slice(&rgba[source..source + 4]);
                        result.la[at * 2..at * 2 + 2].copy_from_slice(&[rgba[source], rgba[source + 3]]);
                    }
                }
            }
        }
    }
    (result, (padding + divisor - 1) / divisor)
}

#[allow(clippy::too_many_arguments)]
fn triangle(
    v: [Point; 3],
    is_top: bool,
    top: &Sprite,
    side: &Sprite,
    corner_heights: &[i16],
    water_height: f32,
    origin: [f32; 2],
    height: i32,
    rgba: &mut [u8],
    depth: &mut [f32],
) {
    let p: [[f32; 2]; 3] = v.map(|point| {
        let q = project(point);
        [q[0] + origin[0], q[1] + origin[1]]
    });
    let cross = |a: [f32; 2], b: [f32; 2], c: [f32; 2]| (a[0] - c[0]) * (b[1] - c[1]) - (a[1] - c[1]) * (b[0] - c[0]);
    let area = cross(p[0], p[1], p[2]);
    if area.abs() < 0.00001 {
        return;
    }
    let minx = p.iter().map(|p| p[0].floor() as i32).min().unwrap().max(0);
    let maxx = p.iter().map(|p| p[0].ceil() as i32).max().unwrap().min(32);
    let miny = p.iter().map(|p| p[1].floor() as i32).min().unwrap().max(0);
    let maxy = p.iter().map(|p| p[1].ceil() as i32).max().unwrap().min(height);
    let sample = ((side.h - 4).max(0) * side.w + side.w / 2) as usize * 4;
    let fallback = &side.rgba[sample..sample + 4];
    let fallback = if fallback[3] != 0 {
        fallback
    } else {
        side.rgba.chunks_exact(4).find(|v| v[3] != 0).unwrap_or(&[0, 0, 0, 255])
    };
    for y in miny..maxy {
        for x in minx..maxx {
            let at = [x as f32 + 0.5, y as f32 + 0.5];
            let weights = [
                cross(p[1], p[2], at) / area,
                cross(p[2], p[0], at) / area,
                cross(p[0], p[1], at) / area,
            ];
            if weights.iter().any(|v| *v < -0.0001) {
                continue;
            }
            let world: Point = std::array::from_fn(|k| (0..3).map(|j| v[j][k] * weights[j]).sum());
            if world[2] < water_height - 0.0001 {
                continue;
            }
            let d = world[0] + world[1] + world[2] / 8.0;
            let pixel = (y * 32 + x) as usize;
            if d < depth[pixel] - 0.0001 {
                continue;
            }
            let source = if is_top { top } else { side };
            let uv = if is_top {
                project([world[0], world[1], 0.0])
            } else {
                [16.0 * (world[0] - world[1]), world[2]]
            };
            let tx = ((uv[0] / 32.0 + 0.5) * source.w as f32).floor() as i32;
            let ty = if is_top {
                ((uv[1] / 16.0 + 0.5) * (source.h - 1) as f32).round() as i32
            } else {
                // Sprite 269 contains a raised soil cap and two rock faces.
                // Sample only the front side band, repeating its original
                // twelve-pixel vertical unit down a taller cliff.
                let u = world[0] + 0.5;
                let v = world[1] + 0.5;
                let upper = f32::from(corner_heights[0]) * (1.0 - u) + f32::from(corner_heights[1]) * u;
                let lower = f32::from(corner_heights[3]) * (1.0 - u) + f32::from(corner_heights[2]) * u;
                let top = (upper * (1.0 - v) + lower * v) * 3.0;
                let down = (top - world[2]).max(0.0).rem_euclid(12.0);
                let native_column = ((tx as f32 + 0.5) * 32.0 / source.w as f32).floor() as i32;
                let upper = 16 - (native_column - 16).abs() / 2;
                (upper + down.floor() as i32) * source.w / 32
            };
            let pos = ((ty.clamp(0, source.h - 1) * source.w + tx.clamp(0, source.w - 1)) * 4) as usize;
            let color = &source.rgba[pos..pos + 4];
            let color = if color[3] != 0 { color } else { fallback };
            rgba[pixel * 4..pixel * 4 + 4].copy_from_slice(color);
            depth[pixel] = d;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn solid(index: u8) -> Sprite {
        Sprite {
            w: 32,
            h: 17,
            rgba: [index, index, index, 255].repeat(32 * 17),
            la: [index, 255].repeat(32 * 17),
        }
    }
    #[test]
    fn raster_has_native_width_exact_fractional_offsets_and_closed_cliffs() {
        let (top, side, water) = (solid(10), solid(20), solid(30));
        for divisor in [1, 2, 4] {
            for rise in [1, 2, 4, 8, 32, 128] {
                let mut key = vec![rise; 12];
                key.push(i16::MIN);
                let (plateau, pad) = raster(&key, &top, &side, &water, divisor);
                assert_eq!(plateau.w, 32 / divisor);
                assert_eq!(pad, 0);
                assert!(plateau.la.chunks_exact(2).any(|p| p[1] == 255));
                key[4..12].fill(0);
                let (cliff, _) = raster(&key, &top, &side, &water, divisor);
                assert!(cliff.la.chunks_exact(2).any(|p| p == [20, 255]));
                for x in 1..cliff.w - 1 {
                    let occupied: Vec<_> = (0..cliff.h)
                        .filter(|y| cliff.la[((y * cliff.w + x) * 2 + 1) as usize] != 0)
                        .collect();
                    if let (Some(first), Some(last)) = (occupied.first(), occupied.last()) {
                        assert_eq!(
                            occupied.len() as i32,
                            last - first + 1,
                            "cliff hole at x {x}, divisor {divisor}, rise {rise}"
                        );
                    }
                }
            }
        }
    }
    #[test]
    fn cliff_material_excludes_the_soil_cap_of_the_raised_reference() {
        let top = solid(10);
        let water = solid(30);
        let mut side = Sprite {
            w: 32,
            h: 29,
            rgba: [99, 99, 99, 255].repeat(32 * 29),
            la: [99, 255].repeat(32 * 29),
        };
        for x in 0_i32..32 {
            let edge = 16 - (x - 16).abs() / 2;
            for y in edge..(edge + 12).min(29) {
                let i = (y * 32 + x) as usize;
                side.rgba[i * 4..i * 4 + 4].copy_from_slice(&[20, 20, 20, 255]);
                side.la[i * 2] = 20;
            }
        }
        let mut key = vec![0; 4];
        key.extend([-32; 8]);
        key.push(i16::MIN);
        let (raster, _) = raster(&key, &top, &side, &water, 1);
        assert!(raster.la.chunks_exact(2).any(|p| p == [20, 255]));
        assert!(!raster.la.chunks_exact(2).any(|p| p == [99, 255]));
    }
    #[test]
    fn wet_raster_keeps_flat_water_and_exposes_actual_shallow_banks() {
        let (top, side, water) = (solid(10), solid(20), solid(30));
        let mut key = vec![0, 4, 4, 0, 0, 4, 4, 4, 4, 0, 0, 0, 2];
        let (image, _) = raster(&key, &top, &side, &water, 1);
        assert!(image.la.chunks_exact(2).any(|p| p == [10, 255]));
        assert!(image.la.chunks_exact(2).any(|p| p == [30, 255]));
        key[..12].fill(0);
        let (image, _) = raster(&key, &top, &side, &water, 1);
        assert!(!image.la.chunks_exact(2).any(|p| p == [10, 255]));
    }
}

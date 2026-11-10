//! Rasterized spatial terrain patches in the existing indexed regional atlas.
//! Corner heights are quarter levels; vertical faces join independent plateaus.

use crate::{Builder, City, Draw, Rect, sprites::Sprite};

pub const FIRST_IMAGE: u64 = 1_400_000_000;
const MASKS: [u8; 16] = [0, 9, 3, 6, 12, 11, 7, 14, 13, 1, 2, 4, 8, 15, 0, 0];
const EDGES: [[usize; 2]; 4] = [[0, 1], [1, 2], [2, 3], [3, 0]];
const POINTS: [[f32; 2]; 4] = [[-0.5, -0.5], [0.5, -0.5], [0.5, 0.5], [-0.5, 0.5]];

fn water_terrain(terrain: u8) -> bool {
    matches!(terrain, 0x10..=0x1e | 0x20..=0x2e | 0x30..=0x3e | 0x40..=0x45)
}

fn water_shape(terrain: u8) -> u8 {
    match terrain {
        0x20..=0x2e => terrain - 0x20,
        0x30..=0x3e => terrain - 0x30,
        0x40..=0x45 => terrain - 0x40 + 15,
        _ => 0,
    }
}

impl City {
    pub(super) fn quarter_corners(&self, index: usize) -> [i16; 4] {
        self.quarter.get(index).copied().unwrap_or_else(|| {
            let mask = MASKS[(self.terrain[index] & 15) as usize];
            std::array::from_fn(|k| (self.land(index) * 4 + if mask & (1 << k) != 0 { 4 } else { 0 }) as i16)
        })
    }
}

impl Builder {
    /// Supply material masks at the actual spatial raster dimensions. Source
    /// sprite masks cannot be stretched onto a cliff or a channel bank.
    pub fn extend_terrain_seasons(&self, masks: &mut std::collections::HashMap<u64, Sprite>) {
        for (&key, mask) in &self.terrain_seasons {
            masks.entry(key).or_insert_with(|| mask.clone());
        }
    }

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
        // Parcel/zone decals remain artwork; only actual terrain is a surface.
        if !self.terrain_models || !(256..=290).contains(&crate::nature::original(sprite).rem_euclid(500)) {
            return self.add(draws, sprite, false, sx, baseline).map(|_| ());
        }
        // The spatial patch already contains the water/land height difference.
        // Its local origin is land, even when classic sprites use a water anchor
        // or a hidden-water view preserves a structure's object altitude.
        let edge = self.city.edge;
        let x = index as i32 / edge;
        let y = index as i32 % edge;
        let terrain = self.city.surface(x, y);
        // Sprite anchors may use water/object altitude, including hidden-water
        // copies and highway underlays. Neither may move the physical seabed.
        let baseline = self.config.top() + (x + y) * self.config.hh() + self.config.height() - self.city.land(index) * self.config.step();
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
        key.push(
            if self.city.wet(index) || (self.city.quarter.is_empty() && water_terrain(terrain)) {
                (self.city.water(index) * 4 - ground) as i16
            } else {
                i16::MIN
            },
        );
        let shape = water_shape(terrain);
        key.push(i16::from(shape) | if self.city.quarter.is_empty() { 256 } else { 0 });
        for (dx, dy) in [(0, -1), (1, 0), (0, 1), (-1, 0)] {
            let water = if x + dx >= 0 && y + dy >= 0 && x + dx < edge && y + dy < edge {
                let n = self.city.index(x + dx, y + dy);
                if self.city.wet(n) || (self.city.quarter.is_empty() && water_terrain(self.city.terrain[n])) {
                    let cap = i32::from(matches!(self.city.surface(x + dx, y + dy), 0x2e | 0x3e)) * 4;
                    (self.city.water(n) * 4 + cap - ground) as i16
                } else {
                    i16::MIN
                }
            } else {
                i16::MIN
            };
            key.push(water);
        }
        let cap = key[12].saturating_add(if shape == 14 { 4 } else { 0 });
        for (s, (dx, dy)) in [(0, -1), (1, 0), (0, 1), (-1, 0)].into_iter().enumerate() {
            let connected = key[12] != i16::MIN && key[14 + s] == cap;
            key.push(if connected {
                i16::from(water_shape(self.city.surface(x + dx, y + dy)))
            } else {
                -1
            });
        }
        let (image, padding) = if let Some(value) = self.quarter_ground_cache.get(&key) {
            *value
        } else {
            let flat = self.sprites.get(self.config.base() + 256, false)?;
            let side = self.sprites.get(self.config.base() + 269, false)?;
            let water = self.sprites.get(self.config.base() + 270, false)?;
            let falling = self.sprites.get(self.config.base() + 284, false)?;
            let (raster, padding, mask) = raster(
                &key,
                &self.sprites.images[&flat],
                &self.sprites.images[&side],
                &self.sprites.images[&water],
                &self.sprites.images[&falling],
                self.config.divisor(),
            );
            let image = FIRST_IMAGE + self.quarter_ground_cache.len() as u64 * 2;
            self.sprite_limit.0 = self.sprite_limit.0.max(raster.w);
            self.sprite_limit.1 = self.sprite_limit.1.max(raster.h);
            if mask.iter().any(|v| *v != 0) {
                let rgba: Vec<u8> = mask
                    .iter()
                    .enumerate()
                    .flat_map(|(i, kind)| {
                        let alpha = raster.rgba[i * 4 + 3];
                        match kind {
                            1 => [0, 0, 153, alpha],
                            2 => [0, 0, 64, alpha],
                            _ => [0, 255, 0, alpha],
                        }
                    })
                    .collect();
                self.terrain_seasons.insert(
                    image,
                    Sprite {
                        w: raster.w,
                        h: raster.h,
                        la: vec![],
                        rgba,
                    },
                );
            }
            self.sprites.images.insert(image, raster);
            self.terrain_water.insert(image, mask);
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

// Shared bank profiles in tile coordinates. The numbered forms describe ports
// and bank corners, not separate meshes or copies of the original pictures.
fn bank(shape: u8, u: f32, v: f32) -> f32 {
    let edges = [v, 1.0 - u, 1.0 - v, u];
    let ramp = |distance: f32, width: f32| ((width - distance) / 0.10).clamp(-1.0, 1.0);
    match shape {
        1..=4 => ramp(edges[[3, 0, 1, 2][(shape - 1) as usize]], 0.10),
        5..=8 => {
            // A circular quarter joins the neighboring straight bank at the
            // same inset and tangent, instead of cutting the lake diagonally.
            let centers = [[1.0, 1.0], [0.0, 1.0], [0.0, 0.0], [1.0, 0.0]];
            let [x, y] = centers[(shape - 5) as usize];
            (((u - x).hypot(v - y) - 0.90) / 0.10).clamp(-1.0, 1.0)
        }
        9..=12 => {
            let centers = [[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]];
            let [x, y] = centers[(shape - 9) as usize];
            ramp((u - x).hypot(v - y), 0.23)
        }
        13 => (((u - 0.5).hypot(v - 0.5) - 0.40) / 0.10).clamp(-1.0, 1.0),
        15 => ramp(edges[1].min(edges[3]), 0.10),
        16 => ramp(edges[0].min(edges[2]), 0.10),
        // A narrow channel opens into a broad reach at its opposite end.
        17..=20 => {
            let (across, along) = match shape {
                17 => (v, u),
                18 => (u, v),
                19 => (v, 1.0 - u),
                _ => (u, 1.0 - v),
            };
            ramp(across.min(1.0 - across), 0.03 + along * 0.07)
        }
        _ => -1.0,
    }
}

fn connected_bank(key: &[i16], shape: u8, u: f32, v: f32) -> f32 {
    let mut profile = bank(shape, u, v);
    // A neighboring open water port cuts a mouth through this tile's visual
    // bank. Actual XQTR ground still takes precedence over this shallow detail.
    for side in 0..4 {
        let neighbor = key.get(18 + side).copied().unwrap_or(-1);
        if neighbor < 0 {
            continue;
        }
        let (cu, cv, cn_u, cn_v) = match side {
            0 => (0.5, 0.0, 0.5, 1.0),
            1 => (1.0, 0.5, 0.0, 0.5),
            2 => (0.5, 1.0, 0.5, 0.0),
            _ => (0.0, 0.5, 1.0, 0.5),
        };
        // Preserve the circular silhouette of already open corner edges.
        if bank(shape, cu, cv) <= 0.0 || bank(neighbor as u8, cn_u, cn_v) >= 0.0 {
            continue;
        }
        let (distance, nu, nv) = match side {
            0 => (v, u, 1.0),
            1 => (1.0 - u, 0.0, v),
            2 => (1.0 - v, u, 0.0),
            _ => (u, 1.0, v),
        };
        let mouth = bank(neighbor as u8, nu, nv);
        let inland = ((distance - 0.40) / 0.10).clamp(-1.0, 1.0);
        profile = profile.min(mouth.max(inland));
    }
    profile
}

fn ground_height(corners: &[i16], u: f32, v: f32) -> f32 {
    let q: [f32; 4] = std::array::from_fn(|k| f32::from(corners[k]));
    if u >= v {
        q[0] * (1.0 - u) + q[1] * (u - v) + q[2] * v
    } else {
        q[0] * (1.0 - v) + q[2] * u + q[3] * (v - u)
    }
}

fn raster(key: &[i16], top: &Sprite, side: &Sprite, water: &Sprite, falling: &Sprite, divisor: i32) -> (Sprite, i32, Vec<u8>) {
    let mut corners: [Point; 4] = std::array::from_fn(|k| vertex(k, key[k]));
    let mut faces = vec![(corners, 0_u8)];
    let shape = key.get(13).copied().unwrap_or(0) as u8;
    let classic = key.get(13).is_some_and(|v| v & 256 != 0);
    let water_q = key[12];
    let bank_surface = water_q != i16::MIN && (1..=20).contains(&shape) && shape != 14;
    let bank_height = |u, v| {
        // A sub-quarter lip preserves SC2000's one-pixel shore rim.
        let profile = f32::from(water_q) + connected_bank(key, shape, u, v) * 0.25;
        if classic {
            profile
        } else {
            profile.max(ground_height(&key[..4], u, v))
        }
    };
    if key[12] != i16::MIN {
        if bank_surface {
            corners = std::array::from_fn(|k| {
                let [x, y] = POINTS[k];
                [x, y, bank_height(x + 0.5, y + 0.5) * 3.0]
            });
            faces.clear();
            // A shallow bed, sloping banks and open ports. Sixteen samples per
            // tile retain native-pixel shore widths without billboard cutouts.
            for y in 0..16 {
                for x in 0..16 {
                    let quad = [[x, y], [x + 1, y], [x + 1, y + 1], [x, y + 1]].map(|[x, y]| {
                        let (u, v) = (x as f32 / 16.0, y as f32 / 16.0);
                        [u - 0.5, v - 0.5, bank_height(u, v) * 3.0]
                    });
                    faces.push((quad, 0));
                }
            }
        }
        let cap = water_q + if shape == 14 { 4 } else { 0 };
        faces.push((std::array::from_fn(|k| vertex(k, cap)), 2));
        for (s, [a, b]) in EDGES.into_iter().enumerate() {
            let neighbor = key.get(14 + s).copied().unwrap_or(water_q);
            let lower = if neighbor == i16::MIN {
                key[4 + s * 2].min(key[5 + s * 2]).max(key[a].min(key[b])).min(water_q)
            } else {
                neighbor
            };
            if lower < cap {
                faces.push(([vertex(a, cap), vertex(b, cap), vertex(b, lower), vertex(a, lower)], 3));
            }
        }
    }
    for (s, [a, b]) in EDGES.into_iter().enumerate() {
        if bank_surface {
            // Follow the actual edge profile. Joining only its two raised
            // corners would put a soil dam across an open channel port.
            for segment in 0..16 {
                let edge_point = |t: f32| {
                    let x = POINTS[a][0] * (1.0 - t) + POINTS[b][0] * t;
                    let y = POINTS[a][1] * (1.0 - t) + POINTS[b][1] * t;
                    let top = [x, y, bank_height(x + 0.5, y + 0.5) * 3.0];
                    let q = f32::from(key[4 + s * 2]) * (1.0 - t) + f32::from(key[5 + s * 2]) * t;
                    (top, [x, y, (q * 3.0).min(top[2])])
                };
                let (a, lower_a) = edge_point(segment as f32 / 16.0);
                let (b, lower_b) = edge_point((segment + 1) as f32 / 16.0);
                if lower_a[2] < a[2] || lower_b[2] < b[2] {
                    faces.push(([a, b, lower_b, lower_a], 1));
                }
            }
            continue;
        }
        let qa = (corners[a][2] / 3.0).ceil() as i16;
        let qb = (corners[b][2] / 3.0).ceil() as i16;
        let lower_a = key[4 + s * 2].min(qa);
        let lower_b = key[5 + s * 2].min(qb);
        if lower_a < qa || lower_b < qb {
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
    let mut mask = vec![0_u8; (32 * height) as usize];
    let origin = [16.0, (height - 9 - padding) as f32];
    for (face, material) in faces {
        for tri in [[0, 1, 2], [0, 2, 3]] {
            triangle(
                [face[tri[0]], face[tri[1]], face[tri[2]]],
                material,
                if material == 2 { water } else { top },
                side,
                falling,
                &key[..4],
                if material >= 2 || key[12] == i16::MIN {
                    f32::NEG_INFINITY
                } else {
                    f32::from(key[12]) * 3.0
                },
                origin,
                height,
                &mut rgba,
                &mut depth,
                &mut mask,
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
    let mut small_mask = vec![0; (width * small_height) as usize];
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
                        small_mask[at] = mask[source / 4];
                    }
                }
            }
        }
    }
    (result, (padding + divisor - 1) / divisor, small_mask)
}

#[allow(clippy::too_many_arguments)]
fn triangle(
    v: [Point; 3],
    material: u8,
    top: &Sprite,
    side: &Sprite,
    falling: &Sprite,
    corner_heights: &[i16],
    water_height: f32,
    origin: [f32; 2],
    height: i32,
    rgba: &mut [u8],
    depth: &mut [f32],
    mask: &mut [u8],
) {
    let is_top = material == 0 || material == 2;
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
            let source = if material == 3 {
                falling
            } else if is_top {
                top
            } else {
                side
            };
            let uv = if is_top {
                project([world[0], world[1], 0.0])
            } else {
                [16.0 * (world[0] - world[1]), world[2]]
            };
            let tx = ((uv[0] / 32.0 + 0.5) * source.w as f32).floor() as i32;
            let ty = if is_top {
                ((uv[1] / 16.0 + 0.5) * (source.h - 1) as f32).round() as i32
            } else if material == 3 {
                // Repeat the indexed falling-water band vertically; preserve
                // its cycling palette addresses instead of baking RGB frames.
                let native_column = ((tx as f32 + 0.5) * 32.0 / source.w as f32).floor();
                let edge = 16.0 - (native_column - 16.0).abs() * 0.5;
                ((edge + (-world[2]).rem_euclid(12.0)) * source.w as f32 / 32.0).floor() as i32
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
            let color = if color[3] != 0 {
                color
            } else if material >= 2 {
                source.rgba.chunks_exact(4).find(|v| v[3] != 0).unwrap_or(fallback)
            } else {
                fallback
            };
            rgba[pixel * 4..pixel * 4 + 4].copy_from_slice(color);
            depth[pixel] = d;
            mask[pixel] = match material {
                2 => 1,
                3 => 2,
                _ => 0,
            };
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
                let (plateau, pad, _) = raster(&key, &top, &side, &water, &water, divisor);
                assert_eq!(plateau.w, 32 / divisor);
                assert_eq!(pad, 0);
                assert!(plateau.la.chunks_exact(2).any(|p| p[1] == 255));
                key[4..12].fill(0);
                let (cliff, _, _) = raster(&key, &top, &side, &water, &water, divisor);
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
        let (raster, _, _) = raster(&key, &top, &side, &water, &water, 1);
        assert!(raster.la.chunks_exact(2).any(|p| p == [20, 255]));
        assert!(!raster.la.chunks_exact(2).any(|p| p == [99, 255]));
    }
    #[test]
    fn wet_raster_keeps_flat_water_and_exposes_actual_shallow_banks() {
        let (top, side, water) = (solid(10), solid(20), solid(30));
        let mut key = vec![0, 4, 4, 0, 0, 4, 4, 4, 4, 0, 0, 0, 2];
        let (image, _, _) = raster(&key, &top, &side, &water, &water, 1);
        assert!(image.la.chunks_exact(2).any(|p| p == [10, 255]));
        assert!(image.la.chunks_exact(2).any(|p| p == [30, 255]));
        key[..12].fill(0);
        let (image, _, _) = raster(&key, &top, &side, &water, &water, 1);
        assert!(!image.la.chunks_exact(2).any(|p| p == [10, 255]));
    }

    #[test]
    fn bank_profiles_rotate_and_keep_channel_ports_open() {
        for i in 0..=64 {
            let u = i as f32 / 64.0;
            for j in 0..=64 {
                let v = j as f32 / 64.0;
                for first in [1, 5, 9] {
                    for offset in 0..4 {
                        assert!((bank(first + offset, u, v) - bank(first + (offset + 1) % 4, 1.0 - v, u)).abs() < 0.00001);
                    }
                }
                assert!((bank(15, u, v) - bank(16, 1.0 - v, u)).abs() < 0.00001);
            }
        }
        for shape in 0..=20 {
            assert!(bank(shape, 0.5, 0.5) <= 0.0, "Every form has open water at its center");
        }
        for shape in [15, 16] {
            for at in [0.0, 1.0] {
                let (u, v) = if shape == 15 { (0.5, at) } else { (at, 0.5) };
                assert!(bank(shape, u, v) < 0.0, "The channel must meet its neighbor without an end wall");
            }
        }
    }

    #[test]
    fn channel_rasters_keep_the_centerline_open_through_both_ports() {
        let (top, side, water, falling) = (solid(10), solid(20), solid(200), solid(201));
        for shape in [15, 16] {
            let mut key = vec![0; 12];
            key.extend([0, shape | 256, 0, 0, 0, 0]);
            let (image, padding, mask) = raster(&key, &top, &side, &water, &falling, 1);
            let origin = (image.h - 9 - padding) as f32;
            for tick in 0..32 {
                let t = (tick as f32 + 0.5) / 32.0 - 0.5;
                let p = project(if shape == 15 { [0.0, t, 0.0] } else { [t, 0.0, 0.0] });
                let x = (16.0 + p[0]).floor() as i32;
                let y = (origin + p[1]).floor() as i32;
                assert_eq!(mask[(y * image.w + x) as usize], 1, "Soil dam on channel {shape}, sample {tick}");
            }
        }
    }

    #[test]
    fn rounded_lake_corners_follow_a_circle_and_join_straight_shores() {
        for step in 0..=64 {
            let a = step as f32 / 64.0 * std::f32::consts::FRAC_PI_2;
            assert!(bank(5, 1.0 - 0.90 * a.cos(), 1.0 - 0.90 * a.sin()).abs() < 0.00001);
            let t = step as f32 / 64.0;
            assert!((bank(5, 1.0, t) - bank(2, 0.5, t)).abs() < 0.00001);
            assert!((bank(5, t, 1.0) - bank(1, t, 0.5)).abs() < 0.00001);
        }
        assert!(bank(5, 0.2, 0.55) > 0.0, "The arc must not collapse to the former straight chamfer");
    }

    #[test]
    fn neighboring_water_ports_open_every_shore_mouth_without_cutting_other_banks() {
        let (top, side, water, falling) = (solid(10), solid(20), solid(200), solid(201));
        let mut cases = 0;
        for (edge, shape) in [2, 3, 4, 1].into_iter().enumerate() {
            for neighbor in 0..=20 {
                let (nu, nv) = match edge {
                    0 => (0.5, 1.0),
                    1 => (0.0, 0.5),
                    2 => (0.5, 0.0),
                    _ => (1.0, 0.5),
                };
                if bank(neighbor, nu, nv) >= 0.0 {
                    continue;
                }
                for classic in [0, 256] {
                    let mut key = vec![0; 12];
                    key.extend([0, shape | classic, 0, 0, 0, 0, -1, -1, -1, -1]);
                    key[18 + edge] = i16::from(neighbor);
                    let (image, padding, mask) = raster(&key, &top, &side, &water, &falling, 1);
                    for step in 1..16 {
                        let d = (step as f32 + 0.5) / 32.0;
                        let (u, v) = match edge {
                            0 => (0.5, d),
                            1 => (1.0 - d, 0.5),
                            2 => (0.5, 1.0 - d),
                            _ => (d, 0.5),
                        };
                        assert!(connected_bank(&key, shape as u8, u, v) < 0.0);
                        let p = project([u - 0.5, v - 0.5, 0.0]);
                        let x = (16.0 + p[0]).floor() as i32;
                        let y = ((image.h - 9 - padding) as f32 + p[1]).floor() as i32;
                        assert_eq!(
                            mask[(y * image.w + x) as usize],
                            1,
                            "Blocked mouth: side {edge}, neighbor {neighbor}, classic {classic}, step {step}"
                        );
                    }
                    key[18 + edge] = -1;
                    let (u, v) = match edge {
                        0 => (0.5, 0.0),
                        1 => (1.0, 0.5),
                        2 => (0.5, 1.0),
                        _ => (0.0, 0.5),
                    };
                    assert!(
                        connected_bank(&key, shape as u8, u, v) > 0.0,
                        "No opening without a connected neighbor"
                    );
                    cases += 1;
                }
            }
        }
        assert!(cases >= 80);
    }

    #[test]
    fn all_water_forms_have_spatial_materials_at_every_native_size() {
        let (top, side, water, falling) = (solid(10), solid(20), solid(200), solid(201));
        let mut cases = 0;
        for divisor in [1, 2, 4] {
            for shape in 0..=20 {
                for classic in [0, 256] {
                    for phase in 0..4 {
                        for corners in [[0, 0, 0, 0], [0, 1, 1, 0], [0, 4, 4, 0], [0, 8, 8, 0], [32, 32, 32, 32]] {
                            for water_q in [0, 2, 4, 8] {
                                let mut key: Vec<i16> = corners.map(|q| q + phase).to_vec();
                                key.extend([0; 8]);
                                key.extend([water_q, shape | classic]);
                                key.extend([i16::MIN; 4]);
                                let (image, _, mask) = raster(&key, &top, &side, &water, &falling, divisor);
                                assert_eq!(mask.len(), (image.w * image.h) as usize);
                                for (pixel, kind) in image.la.chunks_exact(2).zip(&mask) {
                                    assert!(*kind <= 2);
                                    if *kind != 0 {
                                        assert_eq!(pixel, [if *kind == 1 { 200 } else { 201 }, 255]);
                                    }
                                }
                                if (classic != 0 && (1..=20).contains(&shape) && shape != 14) || corners == [0; 4] && phase == 0 {
                                    assert!(mask.contains(&1), "missing water cap: shape {shape}, divisor {divisor}");
                                }
                                cases += 1;
                            }
                        }
                    }
                }
            }
        }
        assert_eq!(cases, 10080);
    }
}

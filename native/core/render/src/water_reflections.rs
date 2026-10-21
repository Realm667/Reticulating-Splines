//! Indexed sprite reflections on visible, horizontal water. Display snapshots only.
//! Pixel centres reflect about each column's projected footprint at the receiving
//! water altitude. No simulation state, random state or original pixels change.
use crate::{Builder, City, Config, Draw, Rect, reflection_facades::Facade, sprites::Sprite};
use std::collections::HashMap;

pub struct WaterPixels {
    /// RGBA: height + 1, palette index, channel axis (bit 7: falling face), coverage.
    pub surface: Vec<u8>,
    pub reflected: Vec<u8>,
    pub emission: Vec<u8>,
    pub seasons: Vec<u8>,
    pub seabed: Vec<u8>,
    pub lights: Vec<u8>,
}

pub fn mirrored_row(row: i32, contact: i32, object_altitude: i32, water_altitude: i32, step: i32) -> i32 {
    // Reflect pixel centres, not their upper edges: (y + .5)' = 2*p - (y + .5).
    2 * (contact + (object_altitude - water_altitude) * step) - row - 1
}

fn cell(city: &City, depth: i64) -> Option<usize> {
    if depth < 0 {
        return None;
    }
    let y = depth % i64::from(city.edge);
    let x = depth / i64::from(city.edge) - y;
    (x >= 0 && y >= 0 && x < i64::from(city.edge) && y < i64::from(city.edge)).then(|| city.index(x as i32, y as i32))
}

fn horizontal_water(draw: &Draw, city: &City, config: Config) -> Option<usize> {
    let offset = draw.sprite - config.base();
    if !(270..=290).contains(&offset) || draw.moving || draw.shadow {
        return None;
    }
    let i = cell(city, draw.depth)?;
    let t = city.terrain[i];
    if offset == 284 {
        let x = i as i32 / city.edge;
        let y = i as i32 % city.edge;
        let bottom = config.top() + (x + y) * config.hh() + config.height() - city.water(i) * config.step();
        // The same sprite also draws stacked map-side walls. Only a real
        // waterfall at its tile anchor has a receiving top face.
        if city.surface(x, y) != crate::ids::terrain_tile_ids::WATERFALL || draw.rect.y + draw.rect.h != bottom || city.water(i) >= 31 {
            return None;
        }
    }
    (city.wet(i) || (0x10..=0x1e).contains(&t) || (0x20..=0x45).contains(&t)).then_some(i)
}

// The waterfall's cap is one altitude level above its foot. Its vertical
// curtains retain their palette/frame animation and never receive flat mirrors.
fn receiving_level(draw: &Draw, city: &City, config: Config, i: usize, x: i32, y: i32) -> Option<i32> {
    if draw.sprite - config.base() != 284 {
        let cx = i as i32 / city.edge;
        let cy = i as i32 % city.edge;
        let raised = config.top() + (cx + cy) * config.hh() + config.height() - (city.water(i) + 1) * config.step();
        let cap = draw.sprite - config.base() == 270
            && city.surface(cx, cy) == crate::ids::terrain_tile_ids::WATERFALL
            && draw.rect.y + draw.rect.h == raised;
        let level = city.water(i) + i32::from(cap);
        return (level < 32).then_some(level);
    }
    let top = draw.rect.y + draw.rect.h - config.height() - config.step();
    let across = (x - draw.rect.x) as f32 + 0.5 - config.hw() as f32;
    let front = (2 * config.hh()) as f32 - across.abs() * 0.5;
    ((y - top) as f32 + 0.5 <= front).then(|| city.water(i) + 1)
}

// A display-only channel axis, not simulated water velocity. Open water stays
// calm; straight narrow reaches use their actual map connections for ripples.
fn water_axis(city: &City, i: usize) -> u8 {
    use crate::ids::terrain_tile_ids::*;
    match city.terrain[i] {
        CHANNEL_NS | CHANNEL_N | CHANNEL_S => return 1,
        CHANNEL_EW | CHANNEL_E | CHANNEL_W => return 2,
        _ => {}
    }
    let x = i as i32 / city.edge;
    let y = i as i32 % city.edge;
    let wet = |x: i32, y: i32| {
        if x < 0 || y < 0 || x >= city.edge || y >= city.edge {
            return false;
        }
        let n = city.index(x, y);
        (city.wet(n)
            || (DEEP_WATER_FIRST..=DEEP_WATER_DRAW_LAST).contains(&city.terrain[n])
            || (SURFACE_WATER_FIRST..=CHANNEL_LAST).contains(&city.terrain[n]))
            && city.terrain[n] != WATERFALL
            && city.water(n) == city.water(i)
    };
    match [wet(x - 1, y), wet(x + 1, y), wet(x, y - 1), wet(x, y + 1)] {
        [true, true, false, false] => 1,
        [false, false, true, true] => 2,
        _ => 0,
    }
}

fn contact_row(draw: &Draw, column: i32, developed: bool) -> i32 {
    // Developed SC2K sprites stand on a diamond footprint. Its front boundary
    // slopes up by half a pixel per column from the centre to either edge.
    // Trees and narrow props use their painter's point anchor instead.
    let inset = if developed {
        ((2 * column + 1 - draw.rect.w).abs() - 1).max(0) / 4
    } else {
        0
    };
    draw.rect.y + draw.rect.h - inset
}

fn bridge(building: u8) -> bool {
    use crate::ids::building_tile_ids::*;
    (SUSPENSION_BRIDGE_1..=POWER_BRIDGE).contains(&building)
        || [HIGHWAY_STRAIGHT_1, HIGHWAY_STRAIGHT_2, HIGHWAY_BRIDGE, REINFORCED_HIGHWAY_BRIDGE].contains(&building)
}

fn contact_twice(draw: &Draw, column: i32, building: u8) -> i32 {
    use crate::ids::building_tile_ids::{DEVELOPED_FIRST, HIGHWAY_STRAIGHT_2};
    if bridge(building) {
        // A bridge stands along one isometric map axis, not at a point. Its
        // projected water contact has slope +/- 1/2, matching the deck and the
        // adjacent spans. Keep half-pixel contacts to avoid staircase seams.
        // Unreinforced highway bridges use the two ordinary elevated highway
        // sprites. Their direction is encoded in the tile ID, not just FLIPPED.
        let along = if draw.flip ^ (building == HIGHWAY_STRAIGHT_2) {
            column - draw.rect.w / 2
        } else {
            draw.rect.w / 2 - 1 - column
        };
        2 * (draw.rect.y + draw.rect.h) + along
    } else {
        2 * contact_row(draw, column, building >= DEVELOPED_FIRST)
    }
}

fn contact_twice_at_foot(draw: &Draw, column: i32, building: u8, sprite: &Sprite) -> i32 {
    let axis = contact_twice(draw, column, building);
    if !bridge(building) {
        return axis;
    }

    // Some bridge sprites include a pier that reaches the waterline. Anchor
    // those columns at their drawn foot, rather than at the raised deck axis;
    // otherwise the pillar and its reflection visibly separate. A foot is an
    // opaque pixel on the last two rows of the sprite, not an arbitrary lower
    // edge from a truss or cable column.
    let bottom = (0..sprite.h).rev().find(|&y| {
        let at = ((y * sprite.w + column) * 4 + 3) as usize;
        sprite.rgba[at] != 0
    });
    if let Some(y) = bottom.filter(|&y| y >= sprite.h - 2) {
        return 2 * (draw.rect.y + y + 1);
    }
    axis
}

fn pier_start(sprite: &Sprite, column: i32) -> i32 {
    let opaque = |row: i32| sprite.rgba[((row * sprite.w + column) * 4 + 3) as usize] != 0;
    let Some(bottom) = (0..sprite.h).rev().find(|&row| opaque(row)) else {
        return sprite.h;
    };
    if bottom < sprite.h - 2 {
        return sprite.h;
    }
    let mut top = bottom;
    while top > 0 && opaque(top - 1) {
        top -= 1;
    }
    top
}

fn auxiliary(artwork: &HashMap<u64, Sprite>, draw: &Draw, sprite: &Sprite, x: i32, y: i32) -> [u8; 4] {
    let Some(mask) = artwork.get(&((draw.sprite as u64) * 2)) else {
        return [0; 4];
    };
    if mask.w != sprite.w || mask.h != sprite.h {
        return [0; 4];
    }
    let x = if draw.flip { mask.w - 1 - x } else { x };
    mask.rgba[((y * mask.w + x) * 4) as usize..((y * mask.w + x) * 4 + 4) as usize]
        .try_into()
        .unwrap()
}

fn plane_cell(city: &City, c: Config, x: i32, y: i32, water: i32) -> Option<usize> {
    let across = (f64::from(x) + 0.5 - f64::from(c.side() + (city.edge + 1) * c.hw())) / f64::from(c.hw());
    let along = (f64::from(y) + 0.5 - f64::from(c.top() - water * c.step())) / f64::from(c.hh());
    let tx = ((along + across) / 2.0).floor() as i32;
    let ty = ((along - across) / 2.0).floor() as i32;
    (tx >= 0 && ty >= 0 && tx < city.edge && ty < city.edge).then(|| city.index(tx, ty))
}

fn unobstructed(city: &City, c: Config, x: i32, start: i32, end: i32, level: i32) -> bool {
    let mut entered_water = false;
    // A reflection may leave its own bank. It may not cross a second raised
    // bank, island or another water level to reach an unrelated water surface.
    for y in (start..=end).step_by(c.hh().max(1) as usize) {
        let Some(i) = plane_cell(city, c, x, y, level) else { return false };
        let wet = city.wet(i) || (0x10..=0x1e).contains(&city.terrain[i]) || (0x30..=0x45).contains(&city.terrain[i]);
        if wet && city.water(i) == level {
            entered_water = true;
        } else if entered_water && city.land(i) >= level {
            return false;
        }
    }
    entered_water
}

impl Builder {
    pub fn water_pixels(
        &mut self,
        bounds: Rect,
        water_indices: &[u8],
        emission: &HashMap<u64, Sprite>,
        seasons: &HashMap<u64, Sprite>,
    ) -> Result<WaterPixels, String> {
        let bytes = bounds.w as usize * bounds.h as usize * 4;
        let mut out = WaterPixels {
            surface: vec![0; bytes],
            reflected: vec![0; bytes],
            emission: vec![0; bytes],
            seasons: vec![0; bytes],
            seabed: vec![0; bytes],
            lights: vec![0; bytes],
        };
        if self.config.underground || water_indices.len() != 256 {
            return Ok(out);
        }
        let mut levels = [false; 32];
        let mut side_beds = Vec::new();
        for draw in self.collect(bounds)? {
            let sprite = &self.sprites.images[&draw.image];
            let footprint = self.sprites.footprint_draw(&draw);
            let water = horizontal_water(&footprint, &self.city, self.config);
            let axis = water.map_or(0, |i| water_axis(&self.city, i));
            let waterfront = cell(&self.city, draw.depth).filter(|&i| {
                let b = self.city.buildings[i];
                water.is_none()
                    && !draw.shadow
                    && !draw.moving
                    && crate::nature::original(draw.sprite) == self.config.base() + i32::from(b)
                    && (bridge(b) || b == crate::ids::building_tile_ids::MARINA)
                    && self.city.wet(i)
            });
            let clipped = draw.rect.clip(bounds);
            for y in clipped.y..clipped.y + clipped.h {
                for x in clipped.x..clipped.x + clipped.w {
                    let src = (((y - draw.rect.y) * sprite.w + x - draw.rect.x) * 4) as usize;
                    if sprite.rgba[src + 3] == 0 {
                        continue;
                    }
                    let dst = (((y - bounds.y) * bounds.w + x - bounds.x) * 4) as usize;
                    out.surface[dst..dst + 4].fill(0);
                    let embedded = waterfront
                        .filter(|_| (140..=166).contains(&auxiliary(seasons, &draw, sprite, x - draw.rect.x, y - draw.rect.y)[2]));
                    if let Some(i) = water.filter(|_| water_indices[sprite.rgba[src] as usize] != 0).or(embedded) {
                        let cap = if embedded.is_some() {
                            Some(self.city.water(i))
                        } else {
                            receiving_level(&footprint, &self.city, self.config, i, x, y)
                        };
                        let side = cap.is_none() && footprint.sprite - self.config.base() == 284;
                        let Some(level) = cap.or_else(|| side.then(|| self.city.water(i) + 1)) else {
                            continue;
                        };
                        levels[level as usize] |= !side;
                        out.surface[dst..dst + 4].copy_from_slice(&[
                            level as u8 + 1,
                            sprite.rgba[src],
                            axis | if side { 128 } else { 0 },
                            255,
                        ]);
                        if side {
                            // The curtain reveals the bank of this cell, not an
                            // unrelated flat seabed projected behind its face.
                            let shade = if x < footprint.rect.x + self.config.hw() { 155 } else { 190 };
                            side_beds.push((dst, [(self.city.land(i) * 255 / 31) as u8, shade, 0, 255]));
                        }
                    }
                }
            }
        }
        if !out.surface.chunks_exact(4).any(|p| p[3] != 0) {
            return Ok(out);
        }
        // Include source sprites outside the output region. A tall source above
        // the viewport may still reflect inside it. The bound covers every saved
        // altitude and the largest sprite in this configured artwork.
        let reach = self.sprite_limit.1 + 62 * self.config.step() + self.sprite_limit.0;
        let sources = self.collect(Rect::new(bounds.x, bounds.y - reach, bounds.w, bounds.h + 2 * reach))?;
        seabed_pixels(&mut out.seabed, bounds, &self.city, self.config);
        self.shore_distances(&mut out.seabed, bounds, water_indices)?;
        for (dst, bed) in side_beds {
            if out.surface[dst + 2] & 128 != 0 && out.surface[dst + 3] != 0 {
                out.seabed[dst..dst + 4].copy_from_slice(&bed);
            }
        }
        let mut owners = vec![i64::MIN; bytes / 4];
        for draw in &sources {
            let Some(i) = cell(&self.city, draw.depth) else { continue };
            if draw.shadow
                || draw.moving
                || crate::nature::original(draw.sprite) != self.config.base() + i32::from(self.city.buildings[i])
                || self.city.buildings[i] == 0
                || draw.image >= 1_u64 << 32
            {
                continue;
            }
            let sprite = &self.sprites.images[&draw.image];
            let altitude = self.city.object(i);
            let building = self.city.buildings[i];
            let facade = if self.sprites.artwork_source(draw.image).is_none() {
                Facade::for_sprite(draw, sprite)
            } else {
                None
            };
            self.water_lights(&mut out, bounds, draw, emission, &levels, facade);
            let footprint = self.sprites.footprint_draw(draw);
            let (left, _) = self.sprites.canvas_padding(draw.image);
            let contacts: Vec<_> = (0..sprite.w)
                .map(|x| {
                    let axis = facade
                        .and_then(|f| f.column(draw, x))
                        .map_or_else(|| contact_twice(&footprint, x - left, building), |v| v.2);
                    let foot = if bridge(building) {
                        contact_twice_at_foot(draw, x, building, sprite)
                    } else {
                        axis
                    };
                    // Only the connected pier uses its drawn water contact. A
                    // disconnected cable or truss above it keeps the deck axis.
                    // Shifting the entire column used to tear that upper artwork.
                    (axis, foot, if bridge(building) { pier_start(sprite, x) } else { sprite.h })
                })
                .collect();
            let lowest = contacts.iter().map(|v| v.0.min(v.1)).min().unwrap();
            let highest = contacts.iter().map(|v| v.0.max(v.1)).max().unwrap();
            for (level, present) in levels.iter().enumerate() {
                if !present || altitude < level as i32 {
                    continue;
                }
                let level = level as i32;
                let lift = 2 * (altitude - level) * self.config.step();
                let far = highest + lift - draw.rect.y - 1;
                let near = lowest + lift - (draw.rect.y + draw.rect.h - 1) - 1;
                if !Rect::new(draw.rect.x, near, draw.rect.w, far - near + 1).clip(bounds).area() {
                    continue;
                }
                let first = (bounds.x - draw.rect.x).max(0);
                let last = (bounds.x + bounds.w - draw.rect.x).min(sprite.w);
                for sx in first..last {
                    let facade_column = facade.and_then(|f| f.column(draw, sx));
                    if facade.is_some() && facade_column.is_none() {
                        continue;
                    }
                    let (axis, foot, pier) = contacts[sx as usize];
                    // Land obstructions are checked once per column and receiver
                    // tile span, rather than once for every reflected pixel.
                    let mut visibility = HashMap::new();
                    for sy in 0..sprite.h {
                        if facade_column.is_some_and(|(top, foot, _)| (sy as f32 + 0.5) < top || sy as f32 + 0.5 >= foot) {
                            continue;
                        }
                        let contact = if sy >= pier { foot } else { axis };
                        let plane = (contact + lift).div_euclid(2);
                        let src = ((sy * sprite.w + sx) * 4) as usize;
                        if sprite.rgba[src + 3] == 0 || 2 * (draw.rect.y + sy) + 1 >= contact {
                            continue;
                        }
                        let y = mirrored_row(draw.rect.y + sy, contact.div_euclid(2), altitude, level, self.config.step())
                            + contact.rem_euclid(2);
                        if y < bounds.y || y >= bounds.y + bounds.h {
                            continue;
                        }
                        let x = draw.rect.x + sx;
                        let pixel = ((y - bounds.y) * bounds.w + x - bounds.x) as usize;
                        let dst = pixel * 4;
                        if out.surface[dst] != level as u8 + 1
                            || out.surface[dst + 2] & 128 != 0
                            || out.surface[dst + 3] == 0
                            || owners[pixel] > draw.order
                        {
                            continue;
                        }
                        let receiver = plane_cell(&self.city, self.config, x, y, level);
                        let visible = *visibility
                            .entry((receiver, plane))
                            .or_insert_with(|| unobstructed(&self.city, self.config, x, plane, y, level));
                        if !visible {
                            continue;
                        }
                        // Reuse the existing mask lookup only for visible reflected
                        // pixels. Embedded water is a receiver, not an upright object.
                        let season = auxiliary(seasons, draw, sprite, sx, sy);
                        if (140..=166).contains(&season[2]) {
                            continue;
                        }
                        let distance = (y - plane).max(0);
                        let fade = (255 - distance * self.config.divisor()).max(0) as u8;
                        owners[pixel] = draw.order;
                        out.reflected[dst..dst + 4].copy_from_slice(&[sprite.rgba[src], 0, 0, fade]);
                        out.emission[dst..dst + 4].copy_from_slice(&if draw.emission_disabled {
                            [0; 4]
                        } else {
                            auxiliary(emission, draw, sprite, sx, sy)
                        });
                        out.seasons[dst..dst + 4].copy_from_slice(&season);
                    }
                }
            }
        }
        Ok(out)
    }

    // Cache a light envelope per authored brightmap column. Only the shader's
    // small wave modulation changes per frame. No simulated light or water state.
    fn water_lights(
        &self,
        out: &mut WaterPixels,
        bounds: Rect,
        draw: &Draw,
        emission: &HashMap<u64, Sprite>,
        levels: &[bool; 32],
        facade: Option<Facade>,
    ) {
        let i = cell(&self.city, draw.depth).expect("validated building draw");
        if draw.emission_disabled || self.city.buildings[i] < crate::ids::building_tile_ids::DEVELOPED_FIRST {
            return;
        }
        let sprite = &self.sprites.images[&draw.image];
        let Some(mask) = emission.get(&((draw.sprite as u64) * 2)) else {
            return;
        };
        if mask.w != sprite.w || mask.h != sprite.h {
            return;
        }
        let c = self.config;
        let footprint = self.sprites.footprint_draw(draw);
        let (left, _) = self.sprites.canvas_padding(draw.image);
        for sx in (bounds.x - draw.rect.x).max(0)..(bounds.x + bounds.w - draw.rect.x).min(sprite.w) {
            let facade_column = facade.and_then(|f| f.column(draw, sx));
            if facade.is_some() && facade_column.is_none() {
                continue;
            }
            let contact = facade_column.map_or_else(|| contact_row(&footprint, sx - left, true), |v| v.2.div_euclid(2));
            let mut color = [0.0_f32; 3];
            let mut energy = 0.0_f32;
            let mut height = 0;
            for sy in 0..sprite.h {
                if facade_column.is_some_and(|(top, foot, _)| (sy as f32 + 0.5) < top || sy as f32 + 0.5 >= foot) {
                    continue;
                }
                if sprite.rgba[((sy * sprite.w + sx) * 4 + 3) as usize] == 0 || draw.rect.y + sy >= contact {
                    continue;
                }
                let light = auxiliary(emission, draw, sprite, sx, sy);
                let alpha = f32::from(light[3]) / 255.0;
                if alpha == 0.0 || light[..3].iter().all(|v| *v == 0) {
                    continue;
                }
                for channel in 0..3 {
                    color[channel] += f32::from(light[channel]) * alpha;
                }
                energy += alpha;
                height = height.max(contact - draw.rect.y - sy);
            }
            if energy == 0.0 {
                continue;
            }
            let rgb = color.map(|v| (v / energy).round() as u8);
            let strength = (energy / sprite.h as f32).sqrt().min(1.0);
            let x = draw.rect.x + sx;
            for (level, present) in levels.iter().enumerate() {
                if !present || self.city.object(i) < level as i32 {
                    continue;
                }
                let level = level as i32;
                let plane = contact + (self.city.object(i) - level) * c.step();
                // Require a nearby receiving shore at this column, not just a
                // distant lake aligned with an inland building. A quay may sit
                // between the facade and water; islands terminate the trail.
                if !unobstructed(&self.city, c, x, plane, plane + c.hh(), level) {
                    continue;
                }
                let length = (height + 24 / c.divisor()).clamp(32 / c.divisor(), 160 / c.divisor());
                let mut visibility = HashMap::new();
                for y in plane.max(bounds.y)..(plane + length).min(bounds.y + bounds.h) {
                    let at = (((y - bounds.y) * bounds.w + x - bounds.x) * 4) as usize;
                    if out.surface[at + 3] == 0 || out.surface[at] != level as u8 + 1 {
                        continue;
                    }
                    let receiver = plane_cell(&self.city, c, x, y, level);
                    if !*visibility
                        .entry(receiver)
                        .or_insert_with(|| unobstructed(&self.city, c, x, plane, y, level))
                    {
                        continue;
                    }
                    let fade = 1.0 - (y - plane) as f32 / length as f32;
                    let alpha = (255.0 * strength * fade * fade).round() as u8;
                    // Bound overlapping sources rather than accumulating an
                    // unbounded glow along a densely developed waterfront.
                    if alpha > out.lights[at + 3] {
                        out.lights[at..at + 4].copy_from_slice(&[rgb[0], rgb[1], rgb[2], alpha]);
                    }
                }
            }
        }
    }

    // The coast belongs to the terrain pass, not the visible water mask. A
    // building, bridge or ship hiding water must never generate a foam ring.
    // A halo larger than the finite field makes neighbouring regions agree.
    fn shore_distances(&mut self, out: &mut [u8], bounds: Rect, water_indices: &[u8]) -> Result<(), String> {
        let divisor = self.config.divisor();
        let radius = 32 / divisor + 2;
        let area = Rect::new(bounds.x - radius, bounds.y - radius, bounds.w + 2 * radius, bounds.h + 2 * radius);
        let mut distance = vec![255_u16; (area.w * area.h) as usize];
        for draw in self.coastal_terrain(area)? {
            let offset = draw.sprite - self.config.base();
            if !(256..=290).contains(&offset) || draw.moving || draw.shadow || offset == 284 {
                continue;
            }
            let water = horizontal_water(&draw, &self.city, self.config).is_some();
            let sprite = &self.sprites.images[&draw.image];
            let clipped = draw.rect.clip(area);
            for y in clipped.y..clipped.y + clipped.h {
                for x in clipped.x..clipped.x + clipped.w {
                    let src = (((y - draw.rect.y) * sprite.w + x - draw.rect.x) * 4) as usize;
                    if sprite.rgba[src + 3] == 0 {
                        continue;
                    }
                    let at = ((y - area.y) * area.w + x - area.x) as usize;
                    distance[at] = if water && (water_indices[sprite.rgba[src] as usize] != 0 || offset == 270) {
                        255
                    } else {
                        0
                    };
                }
            }
        }
        coast_distance_field(&mut distance, area.w, area.h, divisor);
        for y in 0..bounds.h {
            for x in 0..bounds.w {
                out[((y * bounds.w + x) * 4 + 2) as usize] = distance[((y + radius) * area.w + x + radius) as usize] as u8;
            }
        }
        Ok(())
    }
}

// Eight-neighbour chamfer in projected map pixels, with compressed isometric Y.
// 255 means at least 32 map pixels offshore. Computed only with static geometry.
fn coast_distance_field(distance: &mut [u16], width: i32, height: i32, divisor: i32) {
    for reverse in [false, true] {
        for row in 0..height {
            let y = if reverse { height - 1 - row } else { row };
            for column in 0..width {
                let x = if reverse { width - 1 - column } else { column };
                let at = (y * width + x) as usize;
                let sign = if reverse { -1 } else { 1 };
                for (dx, dy, cost) in [(-1, 0, 8), (0, -1, 16), (-1, -1, 18), (1, -1, 18)] {
                    let (nx, ny) = (x + dx * sign, y + dy * sign);
                    if nx >= 0 && ny >= 0 && nx < width && ny < height {
                        distance[at] = distance[at].min(distance[(ny * width + nx) as usize].saturating_add((cost * divisor) as u16));
                    }
                }
            }
        }
    }
}

fn seabed_pixels(out: &mut [u8], bounds: Rect, city: &City, config: Config) {
    let data = crate::data_view::DataCity {
        edge: city.edge as usize,
        visible: city.visible,
        altitude: &city.altitude,
        terrain: &city.terrain,
        flags: &city.flags,
    };
    // The seabed exists beneath every cell, even when a multi-tile building
    // suppresses that cell's individual sprite draw. Bound the grid search by
    // the region and the legal altitude range; never traverse the whole city.
    let mut low = [city.edge; 2];
    let mut high = [0; 2];
    for sx in [bounds.x, bounds.x + bounds.w] {
        for sy in [bounds.y, bounds.y + bounds.h] {
            for altitude in [0, 32] {
                let across = (sx - config.side() - (city.edge + 1) * config.hw()) as f32 / config.hw() as f32;
                let along = (sy - config.top() + altitude * config.step()) as f32 / config.hh() as f32;
                for (axis, coordinate) in [(0, (along + across) * 0.5), (1, (along - across) * 0.5)] {
                    low[axis] = low[axis].min((coordinate.floor() as i32 - 1).clamp(0, city.edge));
                    high[axis] = high[axis].max((coordinate.ceil() as i32 + 1).clamp(0, city.edge));
                }
            }
        }
    }
    // Keep the ordinary back-to-front order for overlapping raised polygons.
    for diagonal in low[0] + low[1]..high[0] + high[1] {
        for tx in low[0]..high[0] {
            let ty = diagonal - tx;
            if ty < low[1] || ty >= high[1] {
                continue;
            }
            let (x, y) = (tx as usize, ty as usize);
            if !data.visible(x * city.edge as usize + y, true) {
                continue;
            }
            // Reuse the height-map's actual seabed polygons, including deep-water
            // slopes and stream banks. These are not random textures or flat tiles.
            let polygon = data.surface_polygon(x, y, true);
            let flat = [
                512.0 + (x + y) as f32 * 8.0,
                520.0 + (x + y) as f32 * 8.0,
                528.0 + (x + y) as f32 * 8.0,
                520.0 + (x + y) as f32 * 8.0,
            ];
            let heights: [f32; 4] = std::array::from_fn(|n| (flat[n] - polygon[n][1]) / 12.0);
            // The height-map also closes the two exposed front faces. Top
            // polygons alone leave triangular holes at raised corners and
            // cliffs; a zero-filled texel then looks like maximum water depth.
            // Rasterize each wall down to its neighbour (or the map floor),
            // before the top, in the same painter order as the terrain view.
            for (side, nx, ny, near_corners, shade) in [(1, x + 1, y, [0, 3], 170), (2, x, y + 1, [1, 0], 155)] {
                let mut lower = [flat[side], flat[side + 1]];
                if nx < data.edge && ny < data.edge && data.visible(nx * data.edge + ny, true) {
                    let neighbour = data.surface_polygon(nx, ny, true);
                    lower = near_corners.map(|n| neighbour[n][1]);
                }
                let bottom = std::array::from_fn::<_, 2, _>(|n| {
                    let p = polygon[side + n];
                    [p[0], p[1].max(lower[n])]
                });
                let wall = [polygon[side], polygon[side + 1], bottom[1], bottom[0]];
                let wall_heights = [
                    heights[side],
                    heights[side + 1],
                    (flat[side + 1] - bottom[1][1]) / 12.0,
                    (flat[side] - bottom[0][1]) / 12.0,
                ];
                for tri in [[0, 1, 2], [0, 2, 3]] {
                    let vertices = tri.map(|n| wall[n].map(|v| v / config.divisor() as f32));
                    seabed_triangle(out, bounds, vertices, tri.map(|n| wall_heights[n]), shade);
                }
            }
            let points = polygon.map(|p| [p[0] / config.divisor() as f32, p[1] / config.divisor() as f32]);
            for tri in [[0, 1, 2], [0, 2, 3]] {
                let vertices = tri.map(|n| points[n]);
                let z = tri.map(|n| heights[n]);
                let grid = [[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]];
                let shade = seabed_shade(tri.map(|n| grid[n]), z);
                seabed_triangle(out, bounds, vertices, z, shade);
            }
        }
    }
}

fn seabed_shade(p: [[f32; 2]; 3], h: [f32; 3]) -> u8 {
    let a = [p[1][0] - p[0][0], p[1][1] - p[0][1]];
    let b = [p[2][0] - p[0][0], p[2][1] - p[0][1]];
    let area = a[0] * b[1] - a[1] * b[0];
    let dx = ((h[1] - h[0]) * b[1] - (h[2] - h[0]) * a[1]) / area;
    let dy = (a[0] * (h[2] - h[0]) - b[0] * (h[1] - h[0])) / area;
    (190.0 + (dy - dx) * 24.0 / (1.0 + dx * dx + dy * dy).sqrt()).clamp(120.0, 230.0) as u8
}

fn seabed_triangle(out: &mut [u8], bounds: Rect, p: [[f32; 2]; 3], h: [f32; 3], shade: u8) {
    let cross = |a: [f32; 2], b: [f32; 2], c: [f32; 2]| (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]);
    let area = cross(p[0], p[1], p[2]);
    if area.abs() < 0.001 {
        return;
    }
    let left = p.iter().map(|v| v[0].floor() as i32).min().unwrap().max(bounds.x);
    let right = p.iter().map(|v| v[0].ceil() as i32).max().unwrap().min(bounds.x + bounds.w);
    let top = p.iter().map(|v| v[1].floor() as i32).min().unwrap().max(bounds.y);
    let bottom = p.iter().map(|v| v[1].ceil() as i32).max().unwrap().min(bounds.y + bounds.h);
    for y in top..bottom {
        for x in left..right {
            let q = [x as f32 + 0.5, y as f32 + 0.5];
            let weights = [
                cross(p[1], p[2], q) / area,
                cross(p[2], p[0], q) / area,
                cross(p[0], p[1], q) / area,
            ];
            if weights.iter().any(|v| *v < -0.0001) {
                continue;
            }
            let altitude = weights.iter().zip(h).map(|(weight, height)| weight * height).sum::<f32>();
            let at = (((y - bounds.y) * bounds.w + x - bounds.x) * 4) as usize;
            out[at..at + 4].copy_from_slice(&[(altitude * 255.0 / 31.0).clamp(0.0, 255.0) as u8, shade, 0, 255]);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn submerged_slopes_and_cliffs_leave_no_depth_holes() {
        for view in 0..3 {
            let mut builder = fixture(view);
            builder.city.altitude.fill(0);
            builder.city.terrain.fill(0x10);
            let c = builder.config;
            let bounds = Rect::new(c.side(), c.top(), 160 / c.divisor(), 160 / c.divisor());
            let mut flat = vec![0; (bounds.w * bounds.h * 4) as usize];
            seabed_pixels(&mut flat, bounds, &builder.city, c);
            let cell = builder.city.index(1, 1);
            for height in [0, 1, 5] {
                builder.city.altitude[cell] = height;
                for shape in 0..14 {
                    builder.city.terrain[cell] = 0x10 + shape;
                    let mut actual = vec![0; flat.len()];
                    seabed_pixels(&mut actual, bounds, &builder.city, c);
                    for (pixel, (base, bed)) in flat.chunks_exact(4).zip(actual.chunks_exact(4)).enumerate() {
                        if base[3] != 0 {
                            assert_eq!(
                                bed[3], 255,
                                "depth hole: view {view}, shape {shape}, height {height}, pixel {pixel}"
                            );
                        }
                    }
                }
            }
        }
    }

    #[test]
    fn seabed_covers_cells_without_sprite_draws() {
        for view in 0..3 {
            let mut builder = fixture(view);
            builder.city.altitude.fill(0);
            builder.city.terrain.fill(0x10);
            builder.city.buildings.fill(112);
            builder.city.zones.fill(0); // no individually anchored building draws
            let c = builder.config;
            let bounds = Rect::new(c.side(), c.top(), 160 / c.divisor(), 160 / c.divisor());
            let mut bed = vec![0; (bounds.w * bounds.h * 4) as usize];
            seabed_pixels(&mut bed, bounds, &builder.city, c);
            for x in 0..builder.city.edge {
                for y in 0..builder.city.edge {
                    let px = (builder.city.edge + x - y + 1) * c.hw();
                    let py = (x + y + 1) * c.hh();
                    assert_eq!(bed[((py * bounds.w + px) * 4 + 3) as usize], 255);
                }
            }
        }
    }

    #[test]
    fn coplanar_seabed_has_no_diagonal_lighting_seam() {
        let grid = [[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]];
        for (dx, dy) in [(0.0, 0.0), (1.0, 0.0), (0.0, -1.0), (1.0, 1.0)] {
            let h = grid.map(|p| 4.0 + p[0] * dx + p[1] * dy);
            let shade = seabed_shade([grid[0], grid[1], grid[2]], [h[0], h[1], h[2]]);
            for tri in [[0, 2, 3], [0, 1, 3], [1, 2, 3], [2, 1, 0]] {
                assert_eq!(shade, seabed_shade(tri.map(|n| grid[n]), tri.map(|n| h[n])));
            }
        }
    }

    #[test]
    fn padded_buildings_keep_reflection_and_light_contact_axes() {
        for view in 0..3 {
            for flip in [false, true] {
                let mut builder = fixture(view);
                let divisor = builder.config.divisor();
                let (width, height, left, right, top, bottom) =
                    (64 / divisor, 80 / divisor, 4 / divisor, 8 / divisor, 12 / divisor, 4 / divisor);
                let key = (view * 500 + 112) as u64 * 2;
                let image = key + u64::from(flip);
                let sprite = Sprite {
                    w: width + left + right,
                    h: height + top + bottom,
                    rgba: vec![],
                    la: vec![],
                };
                builder.sprites.images.insert(image, sprite);
                builder.sprites.registration.insert(key, [width, left, bottom]);
                let offset = if flip { right } else { left };
                let original = Draw::new(image, Rect::new(100, 50, width, height));
                let padded = Draw::new(
                    image,
                    Rect::new(100 - offset, 50 - top, width + left + right, height + top + bottom),
                );
                let footprint = builder.sprites.footprint_draw(&padded);
                for x in 0..width {
                    assert_eq!(contact_twice(&original, x, 112), contact_twice(&footprint, x, 112));
                    assert_eq!(contact_row(&original, x, true), contact_row(&footprint, x, true));
                    assert_eq!(padded.rect.x + x + offset, original.rect.x + x);
                }
            }
        }
    }

    #[test]
    fn coastal_distance_is_scaled_and_saturates_offshore() {
        for divisor in [1, 2, 4] {
            let mut distances = vec![255; 80 * 8];
            for row in 0..8 {
                distances[row * 80] = 0;
            }
            coast_distance_field(&mut distances, 80, 8, divisor);
            assert_eq!(distances[4 * 80 + 2], 16 * divisor as u16);
            assert_eq!(distances[4 * 80 + 40], 255);
        }
    }

    #[test]
    fn objects_do_not_create_coasts_and_padding_does_not_create_seams() {
        let mut builder = fixture(2);
        let c = builder.config;
        let whole = Rect::new(c.side(), c.top() - 32, 160, 160);
        let mut indices = [0; 256];
        indices[96] = 1;
        let mut first = vec![0; (whole.w * whole.h * 4) as usize];
        builder.shore_distances(&mut first, whole, &indices).unwrap();
        let mut builder = fixture(2);
        builder.city.buildings.fill(0);
        let mut without_objects = vec![0; first.len()];
        builder.shore_distances(&mut without_objects, whole, &indices).unwrap();
        assert_eq!(first, without_objects);
        let part = Rect::new(whole.x + 50, whole.y + 20, 80, 100);
        let mut section = vec![0; (part.w * part.h * 4) as usize];
        builder.shore_distances(&mut section, part, &indices).unwrap();
        for y in 0..part.h {
            for x in 0..part.w {
                assert_eq!(
                    first[(((y + 20) * whole.w + x + 50) * 4 + 2) as usize],
                    section[((y * part.w + x) * 4 + 2) as usize]
                );
            }
        }
    }

    fn fixture(view: i32) -> Builder {
        let edge = 4;
        let cells = (edge * edge) as usize;
        let mut city = City {
            edge,
            visible: 32,
            altitude: vec![0; cells],
            terrain: vec![0x10; cells],
            buildings: vec![0; cells],
            zones: vec![0; cells],
            flags: vec![4; cells],
            overlays: vec![0; cells],
            underground: vec![0; cells],
            ..Default::default()
        };
        city.flags[0] = 0;
        city.terrain[0] = 0;
        city.buildings[0] = 0x70;
        city.zones[0] = 0x80;
        let config = Config {
            view,
            underground: false,
            pipes: true,
            subways: true,
            tunnels: true,
            mains: true,
            redraw_ground: false,
            building_ground: false,
            specials: false,
            individual_traffic: false,
            natural_forests: false,
            tree_shadows: true,
            natural_terrain: false,
            phase: 0,
            effects: 0,
        };
        let w = config.hw() * 2;
        let h = config.hh() * 2 + 1;
        let mut water = Sprite {
            w,
            h,
            rgba: vec![0; (w * h * 4) as usize],
            la: vec![0; (w * h * 2) as usize],
        };
        for y in 0..h {
            for x in 0..w {
                if (2 * x + 1 - w).abs() + 2 * (y - config.hh()).abs() <= w {
                    let at = (y * w + x) as usize;
                    water.rgba[at * 4..at * 4 + 4].copy_from_slice(&[96, 96, 96, 255]);
                    water.la[at * 2..at * 2 + 2].copy_from_slice(&[96, 255]);
                }
            }
        }
        let mut building = water.clone();
        building.h = h + 24 / config.divisor();
        building.rgba = vec![0; (building.w * building.h * 4) as usize];
        building.la = vec![0; (building.w * building.h * 2) as usize];
        for y in 0..building.h {
            for x in 0..building.w {
                let at = (y * building.w + x) as usize;
                let index = (40 + y % 20 + x % 5) as u8;
                building.rgba[at * 4..at * 4 + 4].copy_from_slice(&[index, index, index, 255]);
                building.la[at * 2..at * 2 + 2].copy_from_slice(&[index, 255]);
            }
        }
        let images = HashMap::from([
            (((config.base() + 270) * 2) as u64, water.clone()),
            (((config.base() + 256) * 2) as u64, water.clone()),
            (((config.base() + 284) * 2) as u64, water),
            (((config.base() + 0x70) * 2) as u64, building),
        ]);
        Builder::new(city, config, images, [161; 4], 2048, false).unwrap()
    }

    #[test]
    fn actual_sprite_pixels_reflect_only_on_visible_water_at_all_art_sizes() {
        for view in 0..3 {
            let mut builder = fixture(view);
            let c = builder.config;
            let bounds = Rect::new(c.side(), c.top() - 32 / c.divisor(), 160 / c.divisor(), 160 / c.divisor());
            let original_altitude = builder.city.altitude.clone();
            let original_terrain = builder.city.terrain.clone();
            let mut indices = [0; 256];
            indices[96] = 1;
            let result = builder.water_pixels(bounds, &indices, &HashMap::new(), &HashMap::new()).unwrap();
            assert!(result.surface.chunks_exact(4).any(|p| p[3] != 0));
            assert!(result.reflected.chunks_exact(4).any(|p| p[3] != 0), "no reflection in view {view}");
            for (surface, reflected) in result.surface.chunks_exact(4).zip(result.reflected.chunks_exact(4)) {
                if reflected[3] != 0 {
                    assert_eq!(surface[3], 255);
                    assert!((40..=63).contains(&reflected[0]), "reflection invented a source color");
                }
            }
            assert_eq!(builder.city.altitude, original_altitude);
            assert_eq!(builder.city.terrain, original_terrain);
            let disabled = builder.water_pixels(bounds, &[0; 256], &HashMap::new(), &HashMap::new()).unwrap();
            assert!(disabled.surface.iter().all(|v| *v == 0));
        }
    }

    #[test]
    fn mixed_marina_keeps_its_own_embedded_water_receiver() {
        let mut builder = fixture(2);
        let original = builder.config.base() + i32::from(crate::ids::building_tile_ids::MARINA);
        let variant = crate::variants::FIRST + original;
        let sprite = builder.sprites.images[&2224].clone();
        builder.sprites.images.insert(original as u64 * 2, sprite.clone());
        builder.sprites.images.insert(variant as u64 * 2, sprite.clone());
        builder.city.buildings[0] = crate::ids::building_tile_ids::MARINA;
        builder.city.flags[0] = 4;
        builder.city.terrain[0] = 0x10;
        let mut mask = sprite;
        for pixel in mask.rgba.chunks_exact_mut(4) {
            pixel.copy_from_slice(&[0, 0, 140, 255]);
        }
        let c = builder.config;
        let bounds = Rect::new(c.side(), c.top() - 32, 160, 160);
        // No generic water indices: all receivers must come from the marina mask.
        let before = builder
            .water_pixels(
                bounds,
                &[0; 256],
                &HashMap::new(),
                &HashMap::from([(original as u64 * 2, mask.clone())]),
            )
            .unwrap();
        assert!(before.surface.chunks_exact(4).any(|p| p[3] != 0));
        builder.sprites.variants.choices.insert(original, vec![(variant, 100)]);
        builder.sprites.variants.original_weight = 0;
        builder.tiles.clear();
        let after = builder
            .water_pixels(bounds, &[0; 256], &HashMap::new(), &HashMap::from([(variant as u64 * 2, mask)]))
            .unwrap();
        assert_eq!(before.surface, after.surface);
    }

    #[test]
    fn power_changes_remove_only_reflected_building_emission() {
        for view in 0..3 {
            let mut b = fixture(view);
            let c = b.config;
            let bounds = Rect::new(c.side(), c.top() - 32 / c.divisor(), 160 / c.divisor(), 160 / c.divisor());
            let key = ((c.base() + 112) * 2) as u64;
            let mut mask = b.sprites.images[&key].clone();
            mask.rgba.fill(255);
            let masks = HashMap::from([(key, mask)]);
            let mut indices = [0; 256];
            indices[96] = 1;
            let mut city = b.city.clone();
            city.flags[0] |= crate::ids::sc2tile_flags::POWERED;
            b.update(city);
            let on = b.water_pixels(bounds, &indices, &masks, &masks).unwrap();
            assert!(on.emission.iter().any(|p| *p != 0));
            assert!(
                on.lights.chunks_exact(4).any(|p| p[3] != 0),
                "missing waterfront light in view {view}"
            );
            let mut city = b.city.clone();
            city.flags[0] &= !crate::ids::sc2tile_flags::POWERED;
            b.update(city);
            let off = b.water_pixels(bounds, &indices, &masks, &masks).unwrap();
            assert!(off.emission.iter().all(|p| *p == 0));
            assert!(off.lights.iter().all(|p| *p == 0));
            assert_eq!(on.reflected, off.reflected);
            assert_eq!(on.seasons, off.seasons);
            assert_eq!(on.surface, off.surface);
        }
    }

    #[test]
    fn cutaway_walls_and_blue_building_pixels_are_not_receiving_surfaces() {
        let mut builder = fixture(2);
        let mut draw = Draw::new(0, Rect::default());
        draw.depth = 4;
        draw.sprite = 1284;
        assert!(horizontal_water(&draw, &builder.city, builder.config).is_none());
        draw.sprite = 1112;
        assert!(horizontal_water(&draw, &builder.city, builder.config).is_none());
        builder.city.flags[4] = 0;
        builder.city.terrain[4] = 0;
        draw.sprite = 1270;
        assert!(horizontal_water(&draw, &builder.city, builder.config).is_none());
    }

    #[test]
    fn waterfall_caps_receive_at_the_raised_level_but_faces_and_cutaways_do_not() {
        for view in 0..=2 {
            let mut builder = fixture(view);
            let c = builder.config;
            let i = builder.city.index(2, 2);
            builder.city.terrain[i] = crate::ids::terrain_tile_ids::WATERFALL;
            builder.city.altitude[i] = 3 | (3 << 5);
            let bottom = c.top() + 4 * c.hh() + c.height() - 3 * c.step();
            let mut draw = Draw::new(0, Rect::new(50, bottom - c.height() - c.step(), c.hw() * 2, c.height() + c.step()));
            draw.sprite = c.base() + 284;
            draw.depth = i64::from(4 * builder.city.edge + 2);
            assert_eq!(horizontal_water(&draw, &builder.city, c), Some(i));
            let x = draw.rect.x + c.hw();
            assert_eq!(receiving_level(&draw, &builder.city, c, i, x, draw.rect.y + c.hh()), Some(4));
            assert_eq!(receiving_level(&draw, &builder.city, c, i, x, bottom - 1), None);
            draw.rect.y += c.step();
            assert_eq!(horizontal_water(&draw, &builder.city, c), None);
            // An inferred channel waterfall follows the same rule, without
            // changing the stored terrain id or saved water altitude.
            draw.rect.y -= c.step();
            builder.city.terrain[i] = crate::ids::terrain_tile_ids::CHANNEL_NS;
            let high = builder.city.index(1, 2);
            builder.city.altitude[high] = 4 | (4 << 5);
            assert_eq!(horizontal_water(&draw, &builder.city, c), Some(i));
        }
    }

    #[test]
    fn seabed_preserves_actual_sloped_heights() {
        let mut output = vec![0; 16 * 16 * 4];
        seabed_triangle(
            &mut output,
            Rect::new(0, 0, 16, 16),
            [[0.0, 0.0], [16.0, 0.0], [0.0, 16.0]],
            [1.0, 3.0, 1.0],
            190,
        );
        let near = output[(2 * 16 + 1) * 4];
        let raised = output[(2 * 16 + 10) * 4];
        assert!(raised > near, "stored slope was flattened");
        assert_eq!(output[(15 * 16 + 15) * 4 + 3], 0);
    }

    #[test]
    fn water_ripple_axes_follow_narrow_reaches_and_keep_open_water_calm() {
        let mut builder = fixture(2);
        let i = builder.city.index(2, 2);
        assert_eq!(water_axis(&builder.city, i), 0);
        for (x, y) in [(2, 1), (2, 3)] {
            let n = builder.city.index(x, y);
            builder.city.terrain[n] = 0;
            builder.city.flags[n] = 0;
        }
        assert_eq!(water_axis(&builder.city, i), 1);
        let n = builder.city.index(1, 2);
        builder.city.altitude[n] = 1 << 5;
        assert_eq!(water_axis(&builder.city, i), 0, "different water levels are not one channel");
        builder.city.terrain[i] = crate::ids::terrain_tile_ids::CHANNEL_EW;
        assert_eq!(water_axis(&builder.city, i), 2);
    }

    #[test]
    fn separate_regions_include_offscreen_sources_and_match_the_whole_pass() {
        let mut builder = fixture(2);
        let c = builder.config;
        let whole = Rect::new(c.side(), c.top() - 32, 160, 160);
        let mut indices = [0; 256];
        indices[96] = 1;
        builder.city.flags[0] |= crate::ids::sc2tile_flags::POWERED;
        let key = ((c.base() + 112) * 2) as u64;
        let mut mask = builder.sprites.images[&key].clone();
        for pixel in mask.rgba.chunks_exact_mut(4) {
            pixel.copy_from_slice(&[240, 130, 35, 200]);
        }
        let masks = HashMap::from([(key, mask)]);
        let expected = builder.water_pixels(whole, &indices, &masks, &HashMap::new()).unwrap();
        assert!(expected.lights.chunks_exact(4).any(|p| p[3] != 0));
        for (surface, light) in expected.surface.chunks_exact(4).zip(expected.lights.chunks_exact(4)) {
            if light[3] != 0 {
                assert_eq!(surface[3], 255);
                assert_eq!(&light[..3], &[240, 130, 35]);
            }
        }
        let parts = [Rect::new(whole.x, whole.y, 80, 160), Rect::new(whole.x + 80, whole.y + 48, 80, 112)];
        for part in parts {
            let actual = builder.water_pixels(part, &indices, &masks, &HashMap::new()).unwrap();
            for (all, section) in [
                (&expected.surface, &actual.surface),
                (&expected.reflected, &actual.reflected),
                (&expected.seabed, &actual.seabed),
                (&expected.lights, &actual.lights),
            ] {
                for y in 0..part.h {
                    let start = (((part.y - whole.y + y) * whole.w + part.x - whole.x) * 4) as usize;
                    let local = (y * part.w * 4) as usize;
                    assert_eq!(
                        &all[start..start + part.w as usize * 4],
                        &section[local..local + part.w as usize * 4]
                    );
                }
            }
        }
    }

    #[test]
    fn inland_building_does_not_cast_a_waterfront_light_trail() {
        let mut b = fixture(2);
        let c = b.config;
        b.city.flags[0] |= crate::ids::sc2tile_flags::POWERED;
        // Move the shoreline two tile rows away from the facade.
        for x in 0..b.city.edge {
            for y in 0..b.city.edge {
                if x + y <= 3 {
                    let i = b.city.index(x, y);
                    b.city.flags[i] &= !4;
                    b.city.terrain[i] = 0;
                }
            }
        }
        let key = ((c.base() + 112) * 2) as u64;
        let mut mask = b.sprites.images[&key].clone();
        mask.rgba.fill(255);
        let mut indices = [0; 256];
        indices[96] = 1;
        let result = b
            .water_pixels(
                Rect::new(c.side(), c.top() - 32, 160, 160),
                &indices,
                &HashMap::from([(key, mask)]),
                &HashMap::new(),
            )
            .unwrap();
        assert!(result.surface.chunks_exact(4).any(|p| p[3] != 0));
        assert!(result.lights.iter().all(|v| *v == 0));
    }

    #[test]
    fn an_island_blocks_a_reflection_from_reaching_another_water_body() {
        let mut builder = fixture(2);
        let c = builder.config;
        let x = c.side() + (builder.city.edge + 1) * c.hw() - 1;
        assert!(unobstructed(&builder.city, c, x, c.top() + c.hh(), c.top() + 7 * c.hh(), 0));
        let island = builder.city.index(2, 2);
        builder.city.flags[island] = 0;
        builder.city.terrain[island] = 0;
        builder.city.altitude[island] = 1;
        assert!(!unobstructed(&builder.city, c, x, c.top() + c.hh(), c.top() + 7 * c.hh(), 0));
    }

    #[test]
    fn pixel_centres_reflect_exactly_at_each_altitude_and_zoom() {
        for step in [3, 6, 12] {
            for water in [0, 4, 31] {
                let contact = 100;
                let altitude = 31;
                let row = 79;
                let reflected = mirrored_row(row, contact, altitude, water, step);
                assert_eq!(reflected + row + 1, 2 * (contact + (altitude - water) * step));
                assert_eq!(mirrored_row(reflected, contact, altitude, water, step), row);
            }
        }
    }

    #[test]
    fn footprint_columns_and_flips_preserve_alignment() {
        let draw = Draw::new(0, Rect::new(0, 20, 32, 80));
        assert_eq!(contact_row(&draw, 0, true), 93);
        assert_eq!(contact_row(&draw, 15, true), 100);
        for x in 0..32 {
            assert_eq!(contact_row(&draw, x, true), contact_row(&draw, 31 - x, true));
            assert_eq!(contact_row(&draw, x, false), 100);
        }
    }

    #[test]
    fn bridge_contact_tracks_the_diagonal_axis_across_spans_and_flips() {
        use crate::ids::building_tile_ids::*;
        for building in (SUSPENSION_BRIDGE_1..=POWER_BRIDGE).chain([HIGHWAY_BRIDGE, REINFORCED_HIGHWAY_BRIDGE]) {
            let width = 64;
            for flip in [false, true] {
                let mut first = Draw::new(0, Rect::new(100, 200, width, 40));
                first.flip = flip;
                let mut next = first.clone();
                let stride = width / 2;
                next.rect.x += if flip { stride } else { -stride };
                next.rect.y += stride / 2;
                for column in 0..width {
                    let adjacent_column = first.rect.x + column - next.rect.x;
                    assert_eq!(
                        contact_twice(&first, column, building),
                        contact_twice(&next, adjacent_column, building)
                    );
                    if column + 2 < width {
                        let delta = contact_twice(&first, column + 2, building) - contact_twice(&first, column, building);
                        assert_eq!(delta, if flip { 2 } else { -2 });
                    }
                }
            }
        }
    }

    #[test]
    fn bridge_pier_columns_anchor_reflections_at_the_visible_foot() {
        use crate::ids::building_tile_ids::ROAD_BRIDGE;
        let draw = Draw::new(0, Rect::new(100, 200, 32, 67));
        let mut sprite = Sprite {
            w: 32,
            h: 67,
            rgba: vec![0; 32 * 67 * 4],
            la: vec![0; 32 * 67 * 2],
        };
        let put = |sprite: &mut Sprite, x: i32, y: i32| {
            let at = ((y * sprite.w + x) * 4) as usize;
            sprite.rgba[at + 3] = 255;
        };
        let support = 4;
        put(&mut sprite, support, 50);
        put(&mut sprite, support, 65);
        put(&mut sprite, support, 66);

        let deck_axis = contact_twice(&draw, support, ROAD_BRIDGE);
        let foot_axis = contact_twice_at_foot(&draw, support, ROAD_BRIDGE, &sprite);
        assert_ne!(foot_axis, deck_axis, "off-centre pier should override the deck axis");
        assert_eq!(foot_axis, 2 * (draw.rect.y + sprite.h));
        assert_eq!(
            pier_start(&sprite, support),
            65,
            "A separate truss pixel must not move with the pier foot"
        );
        assert_eq!(
            contact_twice_at_foot(&draw, 5, ROAD_BRIDGE, &sprite),
            contact_twice(&draw, 5, ROAD_BRIDGE),
            "truss columns must retain the continuous bridge axis"
        );
    }

    #[test]
    fn bridge_sprite_pixels_reflect_without_rotating_in_both_directions() {
        use crate::ids::{
            building_tile_ids::{HIGHWAY_STRAIGHT_1, HIGHWAY_STRAIGHT_2, ROAD_BRIDGE},
            sc2tile_flags::FLIPPED,
        };
        for building in [ROAD_BRIDGE, HIGHWAY_STRAIGHT_1, HIGHWAY_STRAIGHT_2] {
            for view in 0..3 {
                for flip in [false, true] {
                    let mut builder = fixture(view);
                    let c = builder.config;
                    let width = c.hw() * 2;
                    let height = c.height() + 12 / c.divisor();
                    let mut image = Sprite {
                        w: width,
                        h: height,
                        rgba: vec![0; (width * height * 4) as usize],
                        la: vec![0; (width * height * 2) as usize],
                    };
                    for x in 0..width {
                        let direction = if building == HIGHWAY_STRAIGHT_2 {
                            x - width / 2
                        } else {
                            width / 2 - 1 - x
                        };
                        let plane = (2 * height + direction).div_euclid(2);
                        let row = plane - 16 / c.divisor();
                        let at = (row * width + x) as usize;
                        let index = 40 + x as u8;
                        image.rgba[at * 4..at * 4 + 4].copy_from_slice(&[index, index, index, 255]);
                        image.la[at * 2..at * 2 + 2].copy_from_slice(&[index, 255]);
                    }
                    // A separated pier below one truss column must not shift that
                    // upper column away from the continuous diagonal reflection.
                    for y in height - 2..height {
                        let support = if building == HIGHWAY_STRAIGHT_2 { width / 4 } else { width * 3 / 4 };
                        let at = (y * width + support) as usize;
                        image.rgba[at * 4..at * 4 + 4].copy_from_slice(&[200, 200, 200, 255]);
                        image.la[at * 2..at * 2 + 2].copy_from_slice(&[200, 255]);
                    }
                    builder.city.buildings[0] = building;
                    builder.city.terrain[0] = 0x10;
                    builder.city.flags[0] = 4 | if flip { FLIPPED } else { 0 };
                    builder.sprites.images.insert(((c.base() + i32::from(building)) * 2) as u64, image);
                    let bounds = Rect::new(c.side(), c.top() - 32 / c.divisor(), 160 / c.divisor(), 160 / c.divisor());
                    let mut indices = [0; 256];
                    indices[96] = 1;
                    let out = builder.water_pixels(bounds, &indices, &HashMap::new(), &HashMap::new()).unwrap();
                    let draw = builder
                        .collect(bounds)
                        .unwrap()
                        .into_iter()
                        .find(|d| d.sprite == c.base() + i32::from(building))
                        .unwrap();
                    let mut pixels = 0;
                    for x in 0..width {
                        let original_x = if flip { width - 1 - x } else { x };
                        let direction = if building == HIGHWAY_STRAIGHT_2 {
                            original_x - width / 2
                        } else {
                            width / 2 - 1 - original_x
                        };
                        let source_row = (2 * height + direction).div_euclid(2) - 16 / c.divisor();
                        let axis = 2 * (draw.rect.y + height)
                            + if flip ^ (building == HIGHWAY_STRAIGHT_2) {
                                x - width / 2
                            } else {
                                width / 2 - 1 - x
                            };
                        let y = axis - (draw.rect.y + source_row) - 1;
                        let at = (((y - bounds.y) * bounds.w + draw.rect.x + x - bounds.x) * 4) as usize;
                        if out.surface[at + 3] == 0 {
                            continue;
                        }
                        assert_eq!(
                            out.reflected[at],
                            40 + original_x as u8,
                            "tile {building}, view {view}, flip {flip}, column {x}"
                        );
                        assert!(out.reflected[at + 3] > 0);
                        pixels += 1;
                    }
                    assert!(pixels >= width / 2, "bridge reflection was clipped in view {view}, flip {flip}");
                }
            }
        }
    }
}

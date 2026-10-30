//! Region-only boundary constraints, applied after ordinary terrain generation.
//! Every mutation is staged. Existing cities and the original generator are untouched.

use crate::sim::bytes::write_u32_be;
use crate::sim::city::City;
use crate::sim::ids::{sc2misc_layout as misc, sc2tile_flags as flags};
use crate::sim::tools::terrain;

const STRIDE: usize = 5;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct EdgeCell {
    land: i32,
    water: i32,
    wet: bool,
    salt: bool,
    slope: i32,
}

fn location(side: usize, along: usize, depth: usize, edge: usize) -> usize {
    match side {
        0 => depth * edge + along,
        1 => along * edge + depth,
        2 => (edge - 1 - depth) * edge + along,
        _ => along * edge + edge - 1 - depth,
    }
}

/// Four edges ordered low X, low Y, high X, high Y. Each sample is
/// land height, water height, wet, salt, and the inward first-order slope.
pub fn constrain(city: &mut City, samples: &[i32], sea_level: i64) -> Result<(), String> {
    let edge = usize::try_from(city.map_size).map_err(|_| "Invalid region map size")?;
    if !(16..=4096).contains(&edge) || samples.len() != 4 * edge * STRIDE || !(0..=31).contains(&sea_level) {
        return Err("Invalid region boundary dimensions".into());
    }
    let cells = edge * edge;
    for (data, expected) in [
        (&city.altm.data, cells * 2),
        (&city.xter.data, cells),
        (&city.xbld.data, cells),
        (&city.xzon.data, cells),
        (&city.xbit.data, cells),
    ] {
        if data.len() != expected {
            return Err("Missing region terrain data".into());
        }
    }
    if city.misc.data.len() < misc::SIZE as usize {
        return Err("Missing region city data".into());
    }
    let mut edges = Vec::with_capacity(4 * edge);
    for sample in samples.chunks_exact(STRIDE) {
        if !(0..=31).contains(&sample[0])
            || !(0..=31).contains(&sample[1])
            || !(0..=1).contains(&sample[2])
            || !(0..=1).contains(&sample[3])
            || !(-31..=31).contains(&sample[4])
        {
            return Err("Invalid region boundary sample".into());
        }
        edges.push(EdgeCell {
            land: sample[0],
            water: sample[1],
            wet: sample[2] == 1,
            salt: sample[3] == 1,
            slope: sample[4],
        });
    }
    let mut fixed: Vec<Option<EdgeCell>> = vec![None; cells];
    for side in 0..4 {
        for along in 0..edge {
            let index = location(side, along, 0, edge);
            let value = edges[side * edge + along];
            if let Some(previous) = fixed[index]
                && (previous.land != value.land
                    || previous.wet != value.wet
                    || (value.wet && (previous.water != value.water || previous.salt != value.salt)))
            {
                return Err("Neighboring landscapes have incompatible corner heights or water".into());
            }
            fixed[index] = Some(value);
        }
    }
    // One-level height envelopes propagated from every fixed edge. They make
    // incompatible edited constraints fail instead of silently moving a city edge.
    let mut lower = vec![0; cells];
    let mut upper = vec![31; cells];
    for (index, value) in fixed.iter().enumerate() {
        if let Some(value) = value {
            lower[index] = value.land;
            upper[index] = value.land;
        }
    }
    for _ in 0..2 {
        for index in 0..cells {
            for previous in [index.checked_sub(edge), if index % edge > 0 { index.checked_sub(1) } else { None }]
                .into_iter()
                .flatten()
            {
                lower[index] = lower[index].max(lower[previous] - 1);
                upper[index] = upper[index].min(upper[previous] + 1);
            }
        }
        for index in (0..cells).rev() {
            for next in [
                if index + edge < cells { Some(index + edge) } else { None },
                if index % edge + 1 < edge { Some(index + 1) } else { None },
            ]
            .into_iter()
            .flatten()
            {
                lower[index] = lower[index].max(lower[next] - 1);
                upper[index] = upper[index].min(upper[next] + 1);
            }
        }
    }
    if lower.iter().zip(&upper).any(|(low, high)| low > high) {
        return Err("Neighboring landscapes have incompatible slopes".into());
    }
    let width = (edge / 6).clamp(4, 24);
    let mut heights = vec![0; cells];
    for x in 0..edge {
        for y in 0..edge {
            let index = x * edge + y;
            let original = i32::from(city.altm.data[index * 2 + 1] & 31);
            let distances = [x, y, edge - 1 - x, edge - 1 - y];
            let mut sum = 0.0;
            let mut weight = 0.0;
            for (side, distance) in distances.iter().enumerate() {
                if *distance >= width {
                    continue;
                }
                let sample = edges[side * edge + if side % 2 == 0 { y } else { x }];
                let taper = (1.0 - *distance as f64 / width as f64).powi(2);
                let target = (sample.land + sample.slope.clamp(-1, 1) * (*distance).min(3) as i32).clamp(0, 31);
                sum += f64::from(target) * taper;
                weight += taper;
            }
            let blended = if weight > 0.0 {
                let blend = weight.min(1.0);
                (f64::from(original) * (1.0 - blend) + sum / weight * blend).round() as i32
            } else {
                original
            };
            heights[index] = blended.clamp(lower[index], upper[index]);
        }
    }
    // Enforce slopes inside the new map without changing any fixed boundary.
    for _ in 0..32 {
        let mut changed = false;
        for index in 0..cells {
            for next in [
                if index + edge < cells { Some(index + edge) } else { None },
                if index % edge + 1 < edge { Some(index + 1) } else { None },
            ]
            .into_iter()
            .flatten()
            {
                if heights[index] > heights[next] + 1 {
                    heights[index] = (heights[next] + 1).max(lower[index]);
                    changed = true;
                } else if heights[next] > heights[index] + 1 {
                    heights[next] = (heights[index] + 1).max(lower[next]);
                    changed = true;
                }
            }
        }
        if !changed {
            break;
        }
    }
    let mut altitude = city.altm.data.clone();
    let mut buildings = city.xbld.data.clone();
    let mut xter = city.xter.data.clone();
    let mut zones = city.xzon.data.clone();
    let mut water_flags = city.xbit.data.clone();
    let mut metadata = city.misc.data.clone();
    for (index, height) in heights.iter().enumerate() {
        terrain::set_land_altitude(&mut altitude, index as i64, i64::from(*height));
    }
    write_u32_be(&mut metadata, misc::WATER_LEVEL, sea_level);
    let indices: Vec<i64> = (0..cells as i64).collect();
    terrain::retile_region(
        &mut altitude,
        &mut buildings,
        &mut xter,
        &mut zones,
        &mut water_flags,
        &mut metadata,
        &indices,
        sea_level,
        city.map_size,
    );
    // Preserve inland surface rivers and continue each boundary water section
    // across the transition strip, ending in a basin when it meets no ocean.
    for side in 0..4 {
        for along in 0..edge {
            let sample = edges[side * edge + along];
            for depth in (0..width.min(12)).rev() {
                let index = location(side, along, depth, edge);
                if depth > 0 && fixed[index].is_some() {
                    continue;
                }
                if depth > 0 && (!sample.wet || terrain::land_altitude(&altitude, index as i64) > i64::from(sample.water)) {
                    continue;
                }
                if depth == 0 {
                    terrain::set_land_altitude(&mut altitude, index as i64, i64::from(sample.land));
                }
                if sample.wet {
                    water_flags[index] |= flags::WATER as u8;
                    terrain::set_water_altitude(&mut altitude, index as i64, i64::from(sample.water));
                    buildings[index] = 0;
                    if sample.water <= sample.land {
                        xter[index] = 0x30;
                    }
                } else {
                    water_flags[index] &= !(flags::WATER as u8);
                    xter[index] &= 0x0f;
                }
                if sample.salt && sample.wet {
                    water_flags[index] |= flags::SALT_WATER as u8;
                } else {
                    water_flags[index] &= !(flags::SALT_WATER as u8);
                }
            }
        }
    }
    retile_with_ghosts(&altitude, &water_flags, &edges, &mut xter, edge);
    // Validate exactly what will be committed, after all terrain postprocessing.
    for (index, sample) in fixed.iter().enumerate() {
        if let Some(sample) = sample
            && (terrain::land_altitude(&altitude, index as i64) != i64::from(sample.land)
                || (water_flags[index] & flags::WATER as u8 != 0) != sample.wet
                || (sample.wet
                    && (terrain::water_altitude(&altitude, index as i64) != i64::from(sample.water)
                        || (water_flags[index] & flags::SALT_WATER as u8 != 0) != sample.salt)))
        {
            return Err("Generated region terrain does not match its neighbors".into());
        }
    }
    city.altm.replace(altitude);
    city.xter.replace(xter);
    city.xbld.replace(buildings);
    city.xzon.replace(zones);
    city.xbit.replace(water_flags);
    super::super::tools::new_terrain::recount_buildings(&city.xbld.data, &mut metadata);
    city.misc.replace(metadata);
    Ok(())
}

fn retile_with_ghosts(altitude: &[u8], water_flags: &[u8], edges: &[EdgeCell], output: &mut [u8], edge: usize) {
    let padded = edge + 2;
    let mut heights = vec![0_i64; padded * padded];
    let mut wet = vec![0_u8; padded * padded];
    for x in 0..edge {
        for y in 0..edge {
            let source = x * edge + y;
            let target = (x + 1) * padded + y + 1;
            heights[target] = terrain::land_altitude(altitude, source as i64);
            wet[target] = water_flags[source];
        }
    }
    for side in 0..4 {
        for along in 0..edge {
            let sample = edges[side * edge + along];
            let target = location(side, along + 1, 0, padded);
            heights[target] = i64::from((sample.land - sample.slope.clamp(-1, 1)).clamp(0, 31));
            wet[target] = if sample.wet { flags::WATER as u8 } else { 0 };
        }
    }
    for (corner, nearest) in [
        (0, padded + 1),
        (padded - 1, padded * 2 - 2),
        ((padded - 1) * padded, (padded - 2) * padded + 1),
        (padded * padded - 1, (padded - 1) * padded - 2),
    ] {
        heights[corner] = heights[nearest];
        wet[corner] = wet[nearest];
    }
    for x in 0..edge {
        for y in 0..edge {
            let index = x * edge + y;
            let land = heights[(x + 1) * padded + y + 1];
            let mut mask = 0;
            for (offset, bit) in terrain::NEIGHBOR_OFFSETS.iter().zip(terrain::NEIGHBOR_MASKS) {
                let sample = (x as i64 + 1 + offset.x) as usize * padded + (y as i64 + 1 + offset.y) as usize;
                if heights[sample] > land {
                    mask |= bit;
                }
            }
            let shape = terrain::TERRAIN_SHAPES[mask as usize];
            let shape = if shape == terrain::RAISE_BASIN { 0x0d } else { shape };
            output[index] = if water_flags[index] & flags::WATER as u8 == 0 {
                shape as u8
            } else {
                let level = terrain::water_altitude(altitude, index as i64);
                if level <= land {
                    let water_shape = terrain::water_shape(&wet, x as i64 + 1, y as i64 + 1, padded as i64);
                    (0x30 + water_shape.min(13)) as u8
                } else {
                    (shape + if level - land == 1 { 0x20 } else { 0x10 }) as u8
                }
            };
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sim::new_city::{self, Options};
    use crate::sim::random::{GameLcgRandom, SimRandom};

    fn generated(layout: &str, seed: i64) -> City {
        let document = new_city::template::empty_city(128);
        let mut city = new_city::city_of(&document);
        let options = Options {
            ocean: true,
            river: true,
            hills: 30,
            water: 25,
            trees: 20,
            layout: layout.into(),
            smooth_slopes: true,
            ..Options::default()
        };
        new_city::generate(&mut city, &options, &mut SimRandom::new(seed), &mut GameLcgRandom::new(seed + 3)).unwrap();
        city
    }

    fn samples(city: &City) -> Vec<i32> {
        let edge = city.map_size as usize;
        let mut result = Vec::new();
        for side in 0..4 {
            for along in 0..edge {
                let index = location(side, along, 0, edge);
                let inner = location(side, along, 1, edge);
                let land = terrain::land_altitude(&city.altm.data, index as i64) as i32;
                let wet = city.xbit.data[index] & flags::WATER as u8 != 0;
                result.extend([
                    land,
                    terrain::water_altitude(&city.altm.data, index as i64) as i32,
                    i32::from(wet),
                    i32::from(wet && city.xbit.data[index] & flags::SALT_WATER as u8 != 0),
                    terrain::land_altitude(&city.altm.data, inner as i64) as i32 - land,
                ]);
            }
        }
        result
    }

    #[test]
    fn every_layout_preserves_all_land_and_water_edges() {
        let original = generated("bay", 41);
        let boundary = samples(&original);
        let sea = terrain::sea_level(&original.misc.data);
        for layout in new_city::LAYOUTS {
            let mut candidate = generated(layout, 917);
            constrain(&mut candidate, &boundary, sea).unwrap_or_else(|error| panic!("{layout}: {error}"));
            let actual = samples(&candidate);
            for (want, got) in boundary.chunks_exact(STRIDE).zip(actual.chunks_exact(STRIDE)) {
                assert_eq!(want[0], got[0], "land {layout}");
                assert_eq!(want[2], got[2], "water presence {layout}");
                if want[2] == 1 {
                    assert_eq!(&want[1..4], &got[1..4], "water/salt {layout}");
                }
            }
            assert!(candidate.xter.data.iter().all(|value| *value < 0x40));
        }
    }

    #[test]
    fn deterministic_constraints_and_conflicts_are_atomic() {
        let original = generated("ridge", 82);
        let mut candidate = generated("lake", 15);
        let mut duplicate = generated("lake", 15);
        let boundary = samples(&original);
        let sea = terrain::sea_level(&original.misc.data);
        constrain(&mut candidate, &boundary, sea).unwrap();
        constrain(&mut duplicate, &boundary, sea).unwrap();
        assert_eq!(candidate.altm.data, duplicate.altm.data);
        assert_eq!(candidate.xter.data, duplicate.xter.data);
        assert_eq!(candidate.xbit.data, duplicate.xbit.data);
        let before = candidate.altm.data.clone();
        let mut incompatible = boundary.clone();
        incompatible[0] = (incompatible[0] + 1) % 32;
        assert!(constrain(&mut candidate, &incompatible, sea).is_err());
        assert_eq!(candidate.altm.data, before);
        assert!(constrain(&mut candidate, &boundary[..10], sea).is_err());
        assert_eq!(candidate.altm.data, before);
    }

    #[test]
    fn inland_surface_river_continues_across_transition() {
        let mut candidate = generated("rolling", 99);
        let mut boundary = vec![0; 4 * 128 * STRIDE];
        for sample in boundary.chunks_exact_mut(STRIDE) {
            sample[0] = 10;
        }
        for along in 55..65 {
            let offset = along * STRIDE;
            boundary[offset + 1] = 10;
            boundary[offset + 2] = 1;
        }
        constrain(&mut candidate, &boundary, 0).unwrap();
        for depth in 0..3 {
            assert_ne!(candidate.xbit.data[depth * 128 + 60] & flags::WATER as u8, 0);
        }
    }
}

//! Persistent quarter-height corner geometry. Legacy cities keep their original
//! terrain tools; XQTR is an opt-in Expanded capability, independent of local art.

use std::collections::{HashSet, VecDeque};

use super::city::City;
use super::geom::{Rect2i, Vec2i};
use super::ids::{building_tile_ids as tiles, sc2zone_layout as zone};
use super::tools::commands::landscape::terrain::{TerrainPath, TerrainResult};
use super::tools::commands::{EditBase, ToolArgs};
use super::tools::network;
use super::tools::terrain::{land_altitude, set_land_altitude};
use super::value::Ints32;

pub const HEADER: usize = 16;
pub const MAX_HEIGHT: u16 = 128;
pub const MASKS: [u8; 16] = [0, 9, 3, 6, 12, 11, 7, 14, 13, 1, 2, 4, 8, 15, 0, 0];
pub const EDGE_CORNERS: [[usize; 2]; 4] = [[0, 1], [1, 2], [2, 3], [3, 0]];
const CORNER_OFFSETS: [(i64, i64); 4] = [(0, 0), (1, 0), (1, 1), (0, 1)];
const DIRECTIONS: [(i64, i64); 4] = [(0, -1), (1, 0), (0, 1), (-1, 0)];

pub fn enabled(city: &City) -> bool {
    city.xqtr.present
}

pub fn validate(city: &City) -> Result<(), String> {
    if !enabled(city) {
        return Ok(());
    }
    let data = &city.xqtr.data;
    let cells = (city.map_size * city.map_size) as usize;
    if city.altm.data.len() != cells * 2
        || [&city.xter, &city.xbld, &city.xzon, &city.xbit, &city.xund]
            .iter()
            .any(|chunk| chunk.data.len() != cells)
        || city.xtxt.data.len() < cells
        || city.misc.data.len() < super::ids::sc2misc_layout::WATER_LEVEL as usize + 4
    {
        return Err("Invalid quarter-height terrain data.".into());
    }
    if !city.xexp.present
        || data.len() != HEADER + cells * 8
        || data[..4] != *b"QTR1"
        || u16::from_be_bytes([data[4], data[5]]) as i64 != city.map_size
        || ![1, 2, 4, 8].contains(&data[6])
        || ![0, 2, 4, 8].contains(&data[7])
        || data[8] >= 16
        || data[9..HEADER].iter().any(|v| *v != 0)
        || data[HEADER..]
            .chunks_exact(2)
            .any(|v| u16::from_be_bytes([v[0], v[1]]) > MAX_HEIGHT)
    {
        return Err("Invalid quarter-height terrain data.".into());
    }
    Ok(())
}

pub fn corners(city: &City, index: usize) -> [u16; 4] {
    if enabled(city) && city.xqtr.data.len() >= HEADER + (index + 1) * 8 {
        return std::array::from_fn(|k| {
            let at = HEADER + index * 8 + k * 2;
            u16::from_be_bytes([city.xqtr.data[at], city.xqtr.data[at + 1]])
        });
    }
    let base = land_altitude(&city.altm.data, index as i64) as u16 * 4;
    let mask = MASKS[(city.xter.data[index] & 15) as usize];
    std::array::from_fn(|k| base + if mask & (1 << k) != 0 { 4 } else { 0 })
}

pub fn flat(city: &City, index: usize) -> bool {
    !enabled(city) || corners(city, index).windows(2).all(|v| v[0] == v[1])
}

pub fn network_allowed(city: &City, index: usize) -> bool {
    if !enabled(city) {
        return true;
    }
    let c = corners(city, index);
    // The maximum corner difference also rejects steep diagonal/saddle tiles.
    c.iter().max().unwrap() - c.iter().min().unwrap() <= 4 && c[0] + c[2] == c[1] + c[3]
}

pub fn raw_corners(data: &[u8], index: usize) -> Option<[u16; 4]> {
    if data.len() < HEADER + (index + 1) * 8 {
        return None;
    }
    Some(std::array::from_fn(|k| {
        let p = HEADER + index * 8 + k * 2;
        u16::from_be_bytes([data[p], data[p + 1]])
    }))
}

/// Every occupied tile of a structure must share one exact supporting height.
pub fn raw_level_site(data: &[u8], indices: impl IntoIterator<Item = usize>) -> bool {
    if data.is_empty() {
        return true;
    }
    let mut level = None;
    for i in indices {
        let Some(c) = raw_corners(data, i) else {
            return false;
        };
        if c.iter().any(|q| *q != c[0]) || level.is_some_and(|height| height != c[0]) {
            return false;
        }
        level = Some(c[0]);
    }
    level.is_some()
}

pub fn level_site(city: &City, site: Rect2i) -> bool {
    if !enabled(city) {
        return true;
    }
    if site.size.x <= 0
        || site.size.y <= 0
        || city.index_of(site.position.x, site.position.y) < 0
        || city.index_of(site.end().x - 1, site.end().y - 1) < 0
    {
        return false;
    }
    raw_level_site(
        &city.xqtr.data,
        (site.position.x..site.end().x).flat_map(|x| (site.position.y..site.end().y).map(move |y| (x * city.map_size + y) as usize)),
    )
}

pub fn raw_allowed(data: &[u8], index: usize) -> bool {
    raw_corners(data, index).is_none_or(allowed_corners)
}

pub fn raw_connects(data: &[u8], first: usize, second: usize, direction: usize) -> bool {
    let (Some(a), Some(b)) = (raw_corners(data, first), raw_corners(data, second)) else {
        return true;
    };
    let [a0, a1] = EDGE_CORNERS[direction];
    let [b0, b1] = EDGE_CORNERS[(direction + 2) % 4];
    a[a0] == b[b1] && a[a1] == b[b0]
}

pub fn connects(city: &City, first: usize, second: usize, direction: usize) -> bool {
    if !enabled(city) {
        return true;
    }
    let a = corners(city, first);
    let b = corners(city, second);
    let [a0, a1] = EDGE_CORNERS[direction];
    let [b0, b1] = EDGE_CORNERS[(direction + 2) % 4];
    a[a0] == b[b1] && a[a1] == b[b0]
}

fn store(data: &mut [u8], index: usize, corners: [u16; 4]) {
    for (k, q) in corners.into_iter().enumerate() {
        let at = HEADER + index * 8 + k * 2;
        data[at..at + 2].copy_from_slice(&q.to_be_bytes());
    }
}

/// Rotation turns both tile indices and the corner order. Four turns are exact.
pub fn rotate(city: &mut City, counter_clockwise: bool) {
    if !enabled(city) {
        return;
    }
    let edge = city.map_size;
    let mut data = city.xqtr.data.clone();
    for x in 0..edge {
        for y in 0..edge {
            let (nx, ny) = if counter_clockwise { (y, edge - 1 - x) } else { (edge - 1 - y, x) };
            let source = corners(city, (x * edge + y) as usize);
            let target = std::array::from_fn(|k| source[(k + if counter_clockwise { 1 } else { 3 }) % 4]);
            store(&mut data, (nx * edge + ny) as usize, target);
        }
    }
    city.xqtr.replace(data);
}

/// Raise/lower a plateau by the saved edit step. Shared corners remain shared;
/// selecting Cliff deliberately leaves adjacent plateau heights independent.
pub fn apply(city: &mut City, args: &ToolArgs, path: &TerrainPath) -> TerrainResult {
    if let Err(error) = validate(city) {
        return TerrainResult::rejected(&error, 0);
    }
    if path.target_override > i64::from(MAX_HEIGHT) {
        return TerrainResult::rejected("Invalid quarter-height terrain data.", 0);
    }
    let edge = city.map_size;
    let start = city.index_of(path.start.x, path.start.y);
    if start < 0 || path.points.is_empty() {
        return TerrainResult::rejected("terrain path is outside the city", 0);
    }
    let step = u16::from(city.xqtr.data[6]);
    let grade = u16::from(city.xqtr.data[7]);
    let target = if path.target_override >= 0 {
        path.target_override as u16
    } else {
        *corners(city, start as usize).iter().min().unwrap()
    };
    let mut all: Vec<[u16; 4]> = (0..(edge * edge) as usize).map(|i| corners(city, i)).collect();
    let before = all.clone();
    let mut listed = 0;
    let mut actions = 0;
    let mut insufficient = 0;
    let mut conflicts = 0;
    let mut remainder = u64::from(city.xqtr.data[8]);
    let brush_points = if args.subtool == 1 {
        std::slice::from_ref(&path.start)
    } else {
        path.points
    };
    for point in brush_points {
        let index = city.index_of(point.x, point.y);
        if index < 0 {
            continue;
        }
        let index = index as usize;
        let low = *all[index].iter().min().unwrap();
        let high = *all[index].iter().max().unwrap();
        let next = match args.subtool {
            1 => target,
            2 => high.saturating_add(step).min(MAX_HEIGHT),
            3 => low.saturating_sub(step),
            _ => return TerrainResult::rejected("tool is not a terrain tool", 0),
        };
        let anchors: Vec<usize> = if args.subtool == 1 {
            path.points
                .iter()
                .filter_map(|p| {
                    let i = city.index_of(p.x, p.y);
                    (i >= 0).then_some(i as usize)
                })
                .collect()
        } else {
            vec![index]
        };
        let mut trial = all.clone();
        let mut queue = VecDeque::new();
        let mut pins = HashSet::new();
        for &anchor in &anchors {
            for k in 0..4 {
                pins.insert(vertex_key(&all, edge, anchor, k));
                if grade == 0 {
                    set_corner(&mut trial, &mut queue, anchor, k, next);
                } else {
                    set_shared(&mut trial, &all, edge, &mut queue, anchor, k, next);
                }
            }
        }
        if grade != 0 {
            while let Some((cell, _)) = queue.pop_front() {
                let low = (0..4).min_by_key(|k| trial[cell][*k]).unwrap();
                let high = (0..4).max_by_key(|k| trial[cell][*k]).unwrap();
                let lo = trial[cell][low];
                let hi = trial[cell][high];
                if hi - lo <= grade {
                    continue;
                }
                if pins.contains(&vertex_key(&all, edge, cell, low)) {
                    set_shared(&mut trial, &all, edge, &mut queue, cell, high, lo + grade);
                } else if pins.contains(&vertex_key(&all, edge, cell, high)) {
                    set_shared(&mut trial, &all, edge, &mut queue, cell, low, hi - grade);
                } else {
                    // Project the violating pair toward its nearest valid span.
                    // Odd rounding moves toward the pinned target. Each update
                    // strictly reduces integer squared distance to that target,
                    // so mixed raise/lower grading terminates deterministically.
                    let excess = hi - lo - grade;
                    let raise = excess / 2 + u16::from(!excess.is_multiple_of(2) && lo + hi < next * 2);
                    set_shared(&mut trial, &all, edge, &mut queue, cell, low, lo + raise);
                    set_shared(&mut trial, &all, edge, &mut queue, cell, high, hi - (excess - raise));
                }
            }
        }
        let changed: Vec<_> = (0..trial.len()).filter(|i| trial[*i] != all[*i]).collect();
        if changed.is_empty() {
            continue;
        }
        let protected = changed.iter().any(|i| {
            let b = city.xbld.data[*i];
            b >= tiles::DEVELOPED_FIRST as u8
                || b == tiles::SMALL_PARK as u8
                || b == tiles::RADIOACTIVE_WASTE as u8
                // Engineered highway sections and ramps have fixed supports.
                // Rebuild them after grading, like bridges and buildings.
                || (73..=80).contains(&b)
                || (93..=105).contains(&b)
                || (81..=92).contains(&b)
                || [106, 107].contains(&b)
                || (city.xzon.data[*i] & zone::TYPE_MASK as u8 != 0 && trial[*i].windows(2).any(|v| v[0] != v[1]))
                || (b >= tiles::POWER_LINE_STRAIGHT_1 as u8 && !allowed_corners(trial[*i]))
                || city.xund.data[*i] != 0
                || super::overlay::read(&city.xtxt.data, *i as i64) != 0
                || (b >= 14
                    && (0..4).any(|direction| {
                        let (dx, dy) = DIRECTIONS[direction];
                        let near = city.index_of(*i as i64 / edge + dx, *i as i64 % edge + dy);
                        if near < 0 || !(14..=111).contains(&city.xbld.data[near as usize]) {
                            return false;
                        }
                        let [a, b] = EDGE_CORNERS[direction];
                        let [c, d] = EDGE_CORNERS[(direction + 2) % 4];
                        trial[*i][a] != trial[near as usize][d] || trial[*i][b] != trial[near as usize][c]
                    }))
        });
        if protected {
            conflicts += 1;
            continue;
        }
        let volume: u64 = changed
            .iter()
            .map(|i| (0..4).map(|k| u64::from(trial[*i][k].abs_diff(all[*i][k]))).sum::<u64>())
            .sum();
        // A full tile moved one old level costs 25. Carry sixteenths across
        // strokes: four isolated quarter steps cost exactly 25, not 24 or 28.
        let scaled = volume * 25 + remainder;
        let cost = (scaled / 16) as i64;
        if !args.free_mode && city.funds() - listed < cost {
            insufficient += 1;
            continue;
        }
        if !args.free_mode {
            remainder = scaled % 16;
        }
        listed += cost;
        actions += anchors.iter().filter(|i| all[**i] != [next; 4]).count() as i64;
        all = trial;
    }
    let changed: Vec<_> = (0..all.len()).filter(|i| before[*i] != all[*i]).collect();
    if changed.is_empty() {
        return TerrainResult::rejected(
            if insufficient > 0 {
                "insufficient funds"
            } else if conflicts > 0 {
                "terrain contains protected structures"
            } else {
                "no terrain height changed"
            },
            0,
        );
    }
    let mut data = city.xqtr.data.clone();
    data[8] = remainder as u8;
    for &i in &changed {
        store(&mut data, i, all[i]);
        refresh_tile(city, i, all[i]);
    }
    city.xqtr.replace(data);
    let mut retile = changed.clone();
    for &i in &changed {
        for (dx, dy) in DIRECTIONS {
            let near = city.index_of(i as i64 / edge + dx, i as i64 % edge + dy);
            if near >= 0 {
                retile.push(near as usize);
            }
        }
    }
    retile.sort_unstable();
    retile.dedup();
    for &i in &retile {
        let b = i64::from(city.xbld.data[i]);
        let mode = if (14..=28).contains(&b) {
            Some(network::MODE_POWER)
        } else if (29..=43).contains(&b) {
            Some(network::MODE_ROAD)
        } else if (44..=62).contains(&b) {
            Some(network::MODE_RAIL)
        } else {
            None
        };
        if let Some(mode) = mode {
            let maps = city.maps();
            network::retile_surface(
                maps.buildings,
                maps.terrain,
                maps.zones,
                maps.flags,
                maps.misc,
                Vec2i::new(i as i64 / edge, i as i64 % edge),
                mode,
                maps.text_overlays,
                edge,
            );
        }
    }
    let charged = if args.free_mode { 0 } else { listed };
    city.set_funds(city.funds() - charged);
    let mut result = TerrainResult {
        base: EditBase::accepted("terrain", args.group, args.subtool),
        target_altitude: i64::from(target),
        action_count: actions,
        skipped_conflicts: conflicts,
        skipped_insufficient: insufficient,
        random_used: false,
    };
    result.base.tile_indices = Ints32(retile.iter().map(|i| *i as i32).collect());
    result.base.cost = charged;
    result.base.listed_cost = listed;
    result.base.free_mode = args.free_mode;
    result
}

pub fn refresh_tile(city: &mut City, i: usize, c: [u16; 4]) {
    let low = *c.iter().min().unwrap();
    let mask = c
        .iter()
        .enumerate()
        .fold(0_u8, |bits, (k, q)| bits | if *q > low { 1 << k } else { 0 });
    set_land_altitude(city.altm.mutate(), i as i64, i64::from(low / 4).min(31));
    city.xter.mutate()[i] = MASKS.iter().position(|v| *v == mask).unwrap_or(0) as u8;
    let sea = (city.misc_u32(super::ids::sc2misc_layout::WATER_LEVEL) as u16) * 4;
    let water = super::tools::terrain::water_altitude(&city.altm.data, i as i64) as u16 * 4;
    if low < sea || (city.xbit.data[i] & 4 != 0 && low < water) {
        city.xbit.mutate()[i] |= 4;
        let level = sea.max(water);
        super::tools::terrain::set_water_altitude(city.altm.mutate(), i as i64, i64::from(level / 4));
        city.xter.mutate()[i] += if level - low <= 4 { 0x30 } else { 0x10 };
    } else {
        city.xbit.mutate()[i] &= !4;
    }
}

pub fn sync_legacy_editor(city: &mut City, before: &City, stream: bool) {
    if !enabled(city) {
        return;
    }
    let mut data = city.xqtr.data.clone();
    for i in 0..(city.map_size * city.map_size) as usize {
        let c = if stream
            && (land_altitude(&city.altm.data, i as i64) != land_altitude(&before.altm.data, i as i64)
                || city.xter.data[i] != before.xter.data[i])
        {
            let base = land_altitude(&city.altm.data, i as i64) as u16 * 4;
            let mask = MASKS[(city.xter.data[i] & 15) as usize];
            std::array::from_fn(|k| base + if mask & (1 << k) != 0 { 4 } else { 0 })
        } else {
            corners(before, i)
        };
        store(&mut data, i, c);
        refresh_tile(city, i, c);
    }
    city.xqtr.replace(data);
}

fn allowed_corners(c: [u16; 4]) -> bool {
    c.iter().max().unwrap() - c.iter().min().unwrap() <= 4 && c[0] + c[2] == c[1] + c[3]
}

/// A 2x2 highway follows a continuous cardinal plane without flattening it.
pub fn highway_kind(data: &[u8], edge: i64, anchor: Vec2i, direction: i64) -> Option<i64> {
    if anchor.x < 0 || anchor.y < 0 || anchor.x + 1 >= edge || anchor.y + 1 >= edge {
        return None;
    }
    let first = raw_corners(data, (anchor.x * edge + anchor.y) as usize)?;
    let base = i64::from(first[0]);
    let du = i64::from(first[1]) - base;
    let dv = i64::from(first[3]) - base;
    if du != 0 && dv != 0 {
        return None;
    }
    for dx in 0..2 {
        for dy in 0..2 {
            let c = raw_corners(data, ((anchor.x + dx) * edge + anchor.y + dy) as usize)?;
            if !allowed_corners(c) {
                return None;
            }
            for (k, (cx, cy)) in CORNER_OFFSETS.into_iter().enumerate() {
                if i64::from(c[k]) != base + (dx + cx) * du + (dy + cy) * dv {
                    return None;
                }
            }
        }
    }
    Some(if du > 0 {
        6
    } else if du < 0 {
        4
    } else if dv > 0 {
        7
    } else if dv < 0 {
        5
    } else {
        2 + (direction & 1)
    })
}

/// Bridge bank grading still writes coarse compatibility terrain. Adopt those
/// deliberate changes into the saved mesh before the staged route can commit.
pub fn reconcile_network(city: &mut City, before: &City) -> bool {
    let mut data = city.xqtr.data.clone();
    for i in 0..(city.map_size * city.map_size) as usize {
        let b = city.xbld.data[i];
        if !(14..=111).contains(&b) || (81..=92).contains(&b) || [106, 107].contains(&b) || city.xbit.data[i] & 4 != 0 {
            continue;
        }
        if city.xbld.data[i] == before.xbld.data[i]
            && city.altm.data[i * 2..i * 2 + 2] == before.altm.data[i * 2..i * 2 + 2]
            && city.xter.data[i] == before.xter.data[i]
        {
            continue;
        }
        let c = if land_altitude(&city.altm.data, i as i64) != land_altitude(&before.altm.data, i as i64) {
            let base = land_altitude(&city.altm.data, i as i64) as u16 * 4;
            let mask = MASKS[(city.xter.data[i] & 15) as usize];
            std::array::from_fn(|k| base + if mask & (1 << k) != 0 { 4 } else { 0 })
        } else {
            corners(city, i)
        };
        if !allowed_corners(c) {
            return false;
        }
        store(&mut data, i, c);
        refresh_tile(city, i, c);
    }
    city.xqtr.replace(data);
    true
}

fn vertex_key(original: &[[u16; 4]], edge: i64, cell: usize, corner: usize) -> (i64, u16) {
    let (dx, dy) = CORNER_OFFSETS[corner];
    (
        (cell as i64 / edge + dx) * (edge + 1) + cell as i64 % edge + dy,
        original[cell][corner],
    )
}

#[allow(clippy::too_many_arguments)]
fn set_shared(
    values: &mut [[u16; 4]],
    original: &[[u16; 4]],
    edge: i64,
    queue: &mut VecDeque<(usize, usize)>,
    cell: usize,
    corner: usize,
    height: u16,
) {
    let x = cell as i64 / edge;
    let y = cell as i64 % edge;
    let (dx, dy) = CORNER_OFFSETS[corner];
    for (k, (kx, ky)) in CORNER_OFFSETS.into_iter().enumerate() {
        let nx = x + dx - kx;
        let ny = y + dy - ky;
        if nx < 0 || ny < 0 || nx >= edge || ny >= edge {
            continue;
        }
        let near = (nx * edge + ny) as usize;
        // Different original heights at the same coordinate are a cliff.
        if original[near][k] == original[cell][corner] {
            set_corner(values, queue, near, k, height);
        }
    }
}

fn set_corner(values: &mut [[u16; 4]], queue: &mut VecDeque<(usize, usize)>, index: usize, corner: usize, height: u16) {
    if values[index][corner] != height {
        values[index][corner] = height;
        queue.push_back((index, corner));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sim::city::Chunk;

    fn fixture() -> City {
        let mut city = City::new(8, 4);
        city.altm = Chunk::new(vec![0; 128]);
        city.xter = Chunk::new(vec![0; 64]);
        city.xbld = Chunk::new(vec![0; 64]);
        city.xzon = Chunk::new(vec![0; 64]);
        city.xbit = Chunk::new(vec![0; 64]);
        city.xund = Chunk::new(vec![0; 64]);
        city.xtxt = Chunk::new(vec![0; 64]);
        city.misc = Chunk::new(vec![0; 4800]);
        city.xexp = Chunk::new(vec![0; 160]);
        let mut data = vec![0; HEADER + 64 * 8];
        data[..4].copy_from_slice(b"QTR1");
        data[5] = 8;
        data[6] = 1;
        for i in 0..64 {
            store(&mut data, i, [32; 4]);
            set_land_altitude(&mut city.altm.data, i as i64, 8);
        }
        city.xqtr = Chunk::new(data);
        city.set_funds(1000);
        city
    }

    fn edit(city: &mut City, subtool: i64) -> TerrainResult {
        apply(
            city,
            &ToolArgs {
                group: 0,
                subtool,
                cost: 25,
                free_mode: false,
            },
            &TerrainPath {
                start: Vec2i::new(3, 3),
                points: &[Vec2i::new(3, 3)],
                target_override: -1,
            },
        )
    }

    #[test]
    fn quarter_steps_charge_exact_volume_and_preserve_legacy_scale() {
        let mut city = fixture();
        let costs: Vec<_> = (0..4)
            .map(|_| {
                let r = edit(&mut city, 2);
                assert!(r.base.ok);
                r.base.cost
            })
            .collect();
        assert_eq!(costs, [6, 6, 6, 7]);
        assert_eq!(city.funds(), 975);
        assert_eq!(corners(&city, 27), [36; 4]);
        assert_eq!(land_altitude(&city.altm.data, 27), 9);
        for _ in 0..4 {
            assert!(edit(&mut city, 3).base.ok);
        }
        assert_eq!(corners(&city, 27), [32; 4]);
        assert_eq!(city.funds(), 950);
        assert_eq!(city.xqtr.data[8], 0);
    }

    #[test]
    fn funds_and_structure_failures_are_atomic() {
        let mut city = fixture();
        city.set_funds(5);
        let before = city.xqtr.data.clone();
        assert!(!edit(&mut city, 2).base.ok);
        assert_eq!(city.xqtr.data, before);
        assert_eq!(city.funds(), 5);
        city.set_funds(1000);
        for building in [112, 73, 93, 97] {
            city.xbld.data[27] = building;
            assert!(!edit(&mut city, 2).base.ok);
            assert_eq!(city.xqtr.data, before);
            assert_eq!(city.funds(), 1000);
        }
    }

    #[test]
    fn gentle_normal_steep_and_cliff_network_rules() {
        let mut city = fixture();
        for (shape, allowed) in [
            ([32, 34, 34, 32], true),
            ([32, 36, 36, 32], true),
            ([32, 40, 40, 32], false),
            ([32, 34, 32, 34], false),
        ] {
            for turn in 0..4 {
                let mut c = shape;
                c.rotate_left(turn);
                store(&mut city.xqtr.data, 27, c);
                assert_eq!(network_allowed(&city, 27), allowed);
            }
        }
        store(&mut city.xqtr.data, 27, [33; 4]);
        assert!(!connects(&city, 27, 28, 2));
        store(&mut city.xqtr.data, 28, [33; 4]);
        assert!(connects(&city, 27, 28, 2));
        assert!(raw_level_site(&city.xqtr.data, [27, 28]));
        store(&mut city.xqtr.data, 28, [34; 4]);
        assert!(!raw_level_site(&city.xqtr.data, [27, 28]));
    }

    #[test]
    fn gradual_brush_preserves_shared_vertices_and_four_rotations() {
        let mut city = fixture();
        city.set_funds(100000);
        city.xqtr.data[7] = 2;
        for _ in 0..8 {
            assert!(edit(&mut city, 2).base.ok);
        }
        for x in 0..8 {
            for y in 0..8 {
                let i = x * 8 + y;
                let c = corners(&city, i);
                assert!(c.iter().max().unwrap() - c.iter().min().unwrap() <= 2);
                if x < 7 {
                    assert!(connects(&city, i, i + 8, 1));
                }
                if y < 7 {
                    assert!(connects(&city, i, i + 1, 2));
                }
            }
        }
        let before = city.xqtr.data.clone();
        for _ in 0..4 {
            rotate(&mut city, true);
        }
        assert_eq!(city.xqtr.data, before);
        rotate(&mut city, false);
        rotate(&mut city, true);
        assert_eq!(city.xqtr.data, before);
    }

    #[test]
    fn leveling_mixed_slopes_pins_the_whole_brush_and_refines_to_gentle() {
        let mut city = fixture();
        city.set_funds(1000000);
        city.xqtr.data[6] = 8;
        city.xqtr.data[7] = 8;
        assert!(edit(&mut city, 2).base.ok);
        city.xqtr.data[6] = 1;
        city.xqtr.data[7] = 2;
        let points = [Vec2i::new(4, 3), Vec2i::new(4, 4)];
        let result = apply(
            &mut city,
            &ToolArgs {
                group: 0,
                subtool: 1,
                cost: 25,
                free_mode: false,
            },
            &TerrainPath {
                start: points[0],
                points: &points,
                target_override: 36,
            },
        );
        assert!(result.base.ok, "{}", result.base.error);
        for p in points {
            assert_eq!(corners(&city, (p.x * 8 + p.y) as usize), [36; 4]);
        }
        for i in 0..64 {
            let c = corners(&city, i);
            assert!(c.iter().max().unwrap() - c.iter().min().unwrap() <= 2, "{i}: {c:?}");
            if i / 8 < 7 {
                assert!(connects(&city, i, i + 8, 1));
            }
            if i % 8 < 7 {
                assert!(connects(&city, i, i + 1, 2));
            }
        }
    }

    #[test]
    fn rejects_malformed_and_unflagged_payloads() {
        let mut city = fixture();
        assert!(validate(&city).is_ok());
        city.xqtr.data[8] = 16;
        assert!(validate(&city).is_err());
        city.xqtr.data[8] = 0;
        city.xexp.present = false;
        assert!(validate(&city).is_err());
        city.xexp.present = true;
        city.xqtr.data.pop();
        assert!(validate(&city).is_err());
        let mut city = fixture();
        city.xbld.data.pop();
        assert!(validate(&city).is_err());
    }
}

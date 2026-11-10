//! Versioned Expanded rewards. XEXP owns identity; legacy occupancy cells are
//! inert statue carriers without original microsimulation or reward records.
//! Older readers must reject the required rs.expanded.v1 capability.
use super::bytes::{read_u32_be, write_u32_be};
use super::city::{Chunk, City};
use super::geom::{Rect2i, Vec2i};
use super::ids::{building_tile_ids as tiles, sc2misc_layout as misc, sc2tile_flags as flags};
use super::tools::commands::{EditBase, building::BuildingResult};
use super::value::Ints32;

pub const SIZE: usize = 160;
pub const CARRIER: u8 = tiles::STATUE as u8;
pub const FEATURE: &str = "rs.expanded.v1";
pub const FIRST_TOOL: i64 = 9;
pub const AREAS: [i64; 8] = [4, 4, 5, 4, 4, 3, 5, 6];
pub const THRESHOLDS: [i64; 8] = [150_000, 250_000, 400_000, 650_000, 1_000_000, 1_500_000, 2_500_000, 4_000_000];
pub const COSTS: [i64; 8] = [0, 0, 0, 25_000, 40_000, 0, 60_000, 0];
pub const ANNUAL_COSTS: [i64; 8] = [120, 240, 120, 600, 1200, 240, 1200, 600];

pub fn enabled(city: &City) -> bool {
    city.xexp.present && city.xexp.data.len() == SIZE && &city.xexp.data[..4] == b"EXP1"
}

pub fn initial(city: &City) -> Vec<u8> {
    let mut data = vec![0; SIZE];
    data[..4].copy_from_slice(b"EXP1");
    write_u32_be(&mut data, 8, city.age_in_days() / 25);
    data
}

pub fn enable(city: &mut City) {
    if !enabled(city) {
        city.xexp = Chunk::new(initial(city));
        city.xexp.written = true;
    }
    unlock(city);
}

pub fn site(city: &City, kind: usize) -> Option<Rect2i> {
    if !enabled(city) || kind >= 8 {
        return None;
    }
    let offset = 32 + kind as i64 * 16;
    if read_u32_be(&city.xexp.data, offset) == 0 {
        return None;
    }
    Some(Rect2i::from(
        Vec2i::new(read_u32_be(&city.xexp.data, offset + 4), read_u32_be(&city.xexp.data, offset + 8)),
        Vec2i::new(AREAS[kind], AREAS[kind]),
    ))
}

pub fn at(city: &City, point: Vec2i) -> Option<usize> {
    (0..8).find(|&kind| {
        site(city, kind).is_some_and(|s| {
            point.x >= s.position.x && point.y >= s.position.y && point.x < s.position.x + s.size.x && point.y < s.position.y + s.size.y
        })
    })
}

pub fn indices(city: &City, rect: Rect2i) -> Vec<i64> {
    let mut result = Vec::new();
    for x in rect.position.x..rect.position.x + rect.size.x {
        for y in rect.position.y..rect.position.y + rect.size.y {
            let index = city.index_of(x, y);
            if index >= 0 {
                result.push(index);
            }
        }
    }
    result
}

pub fn validate(city: &City) -> Result<(), String> {
    if !city.xexp.present {
        return Ok(());
    }
    if !enabled(city) {
        return Err("Unsupported Expanded city data.".into());
    }
    let mut occupied = std::collections::HashSet::new();
    for kind in 0..8 {
        if let Some(rect) = site(city, kind) {
            if rect.position.x < 0
                || rect.position.y < 0
                || rect.position.x + rect.size.x > city.map_size
                || rect.position.y + rect.size.y > city.map_size
            {
                return Err("Invalid Expanded building footprint.".into());
            }
            for index in indices(city, rect) {
                if !occupied.insert(index) || city.xbld.data.get(index as usize) != Some(&CARRIER) {
                    return Err("Invalid Expanded building occupancy.".into());
                }
            }
        }
    }
    Ok(())
}

pub fn unlock(city: &mut City) {
    if !enabled(city) {
        return;
    }
    let population = city.misc_u32(misc::NORMAL_POPULATION) + city.misc_u32(misc::ARCOLOGY_POPULATION);
    let peak = read_u32_be(&city.xexp.data, 4).max(population);
    let mask = THRESHOLDS
        .iter()
        .enumerate()
        .fold(read_u32_be(&city.xexp.data, 12), |mask, (n, &limit)| {
            mask | if peak >= limit { 1 << n } else { 0 }
        });
    if peak != read_u32_be(&city.xexp.data, 4) || mask != read_u32_be(&city.xexp.data, 12) {
        write_u32_be(city.xexp.mutate(), 4, peak);
        write_u32_be(city.xexp.mutate(), 12, mask);
    }
}

pub fn available(city: &City, kind: usize) -> bool {
    enabled(city) && kind < 8 && read_u32_be(&city.xexp.data, 12) & (1 << kind) != 0 && site(city, kind).is_none()
}

pub fn footprint(point: Vec2i, area: i64) -> Rect2i {
    let inset = (area - 1) / 2;
    Rect2i::from(Vec2i::new(point.x - inset, point.y - inset), Vec2i::new(area, area))
}

pub fn preview(city: &City, kind: usize, point: Vec2i) -> &'static str {
    if !available(city, kind) {
        return "This metropolis reward is not available.";
    }
    if city.funds() < COSTS[kind] {
        return "Insufficient funds.";
    }
    let rect = footprint(point, AREAS[kind]);
    if rect.position.x < 1
        || rect.position.y < 1
        || rect.position.x + rect.size.x >= city.map_size
        || rect.position.y + rect.size.y >= city.map_size
    {
        return "The building must fit inside the city.";
    }
    let height = city.land_altitude(point.x, point.y);
    for index in indices(city, rect) {
        let n = index as usize;
        if !super::quarter_terrain::flat(city, n)
            || (super::quarter_terrain::enabled(city)
                && super::quarter_terrain::corners(city, n)[0]
                    != super::quarter_terrain::corners(city, (point.x * city.map_size + point.y) as usize)[0])
            || city.xbld.data[n] != 0
            || city.xter.data[n] != 0
            || city.altitude_word(index) & 31 != height
            || city.xbit.data[n] as i64 & flags::WATER != 0
            || city.xzon.data[n] & 15 != 0
            || super::overlay::read(&city.xtxt.data, index) != 0
        {
            return "Metropolis rewards need clear, flat, unzoned land.";
        }
    }
    ""
}

pub fn place(city: &mut City, kind: usize, point: Vec2i, random: i64, lfsr: i64) -> BuildingResult {
    unlock(city);
    let error = preview(city, kind, point);
    if !error.is_empty() {
        return BuildingResult::rejected(error, 0);
    }
    let rect = footprint(point, AREAS[kind]);
    let cells = indices(city, rect);
    for &index in &cells {
        let n = index as usize;
        city.xbld.mutate()[n] = CARRIER;
        city.xzon.mutate()[n] = 0;
        city.xbit.mutate()[n] |= flags::POWERABLE as u8;
    }
    // The carrier has no XMIC entry and never consumes an original reward bit.
    let offset = 32 + kind as i64 * 16;
    let sequence = read_u32_be(&city.xexp.data, 16) + 1;
    write_u32_be(city.xexp.mutate(), 16, sequence);
    write_u32_be(city.xexp.mutate(), offset, sequence);
    write_u32_be(city.xexp.mutate(), offset + 4, rect.position.x);
    write_u32_be(city.xexp.mutate(), offset + 8, rect.position.y);
    write_u32_be(city.xexp.mutate(), offset + 12, 1);
    city.set_funds(city.funds() - COSTS[kind]);
    let mut result = BuildingResult {
        base: EditBase::accepted("building", 5, FIRST_TOOL + kind as i64),
        ..Default::default()
    };
    result.base.site = rect;
    result.base.tile_indices = Ints32(cells.iter().map(|&n| n as i32).collect());
    result.base.cost = COSTS[kind];
    result.base.listed_cost = COSTS[kind];
    result.base.random_state_before = random;
    result.base.random_state_after = random;
    result.lfsr_state_before = lfsr;
    result.lfsr_state_after = lfsr;
    result.tile_id = 256 + kind as i64;
    result
}

/// Clear only this object's carriers, keeping damage and independently changed cells.
pub fn remove(city: &mut City, kind: usize) -> Vec<i64> {
    let Some(rect) = site(city, kind) else {
        return Vec::new();
    };
    let cells = indices(city, rect);
    for &index in &cells {
        let n = index as usize;
        if city.xbld.data[n] == CARRIER {
            city.xbld.mutate()[n] = 0;
            city.xzon.mutate()[n] = 0;
            city.xbit.mutate()[n] &= !((flags::POWERABLE | flags::POWERED) as u8);
        }
    }
    write_u32_be(city.xexp.mutate(), 32 + kind as i64 * 16, 0);
    cells
}

pub fn reconcile(city: &mut City) {
    if !enabled(city) {
        return;
    }
    for kind in 0..8 {
        if let Some(rect) = site(city, kind) {
            let damaged = indices(city, rect).iter().any(|&n| city.xbld.data[n as usize] != CARRIER);
            if damaged {
                remove(city, kind);
            }
        }
    }
    unlock(city);
}

pub fn operational(city: &City, kind: usize) -> bool {
    let Some(rect) = site(city, kind) else {
        return false;
    };
    read_u32_be(&city.xexp.data, 44 + kind as i64 * 16) != 0
        && indices(city, rect)
            .iter()
            .any(|&i| city.xbit.data[i as usize] as i64 & flags::POWERED != 0)
}

/// Monthly upkeep is settled once, including across save/reload and repeated calls.
pub fn monthly(city: &mut City) {
    if !enabled(city) {
        return;
    }
    let month = city.age_in_days() / 25;
    let previous = read_u32_be(&city.xexp.data, 8);
    if month <= previous {
        return;
    }
    let year = month / 12;
    if read_u32_be(&city.xexp.data, 28) != year {
        write_u32_be(city.xexp.mutate(), 24, 0);
        write_u32_be(city.xexp.mutate(), 28, year);
    }
    let mut charged = 0;
    for (kind, &annual) in ANNUAL_COSTS.iter().enumerate() {
        if site(city, kind).is_none() {
            continue;
        }
        let cost = annual / 12 * (month - previous);
        let paid = city.funds() >= cost;
        if paid {
            city.set_funds(city.funds() - cost);
            charged += cost;
        }
        write_u32_be(city.xexp.mutate(), 44 + kind as i64 * 16, i64::from(paid));
    }
    write_u32_be(city.xexp.mutate(), 8, month);
    write_u32_be(city.xexp.mutate(), 20, charged);
    let ytd = read_u32_be(&city.xexp.data, 24) + charged;
    write_u32_be(city.xexp.mutate(), 24, ytd);
}

pub fn rotate(city: &mut City, clockwise: bool) {
    for kind in 0..8 {
        if let Some(rect) = site(city, kind) {
            let (x, y) = if clockwise {
                (city.map_size - rect.position.y - rect.size.y, rect.position.x)
            } else {
                (rect.position.y, city.map_size - rect.position.x - rect.size.x)
            };
            write_u32_be(city.xexp.mutate(), 36 + kind as i64 * 16, x);
            write_u32_be(city.xexp.mutate(), 40 + kind as i64 * 16, y);
        }
    }
}

/// A small, precomputed set of active parcels; no per-tile funding scans.
pub fn influences(city: &City) -> Vec<(Rect2i, i64, i64, bool)> {
    [
        (0, 10, 8, false),
        (1, 12, 10, false),
        (2, 20, 16, false),
        (3, 16, 16, true),
        (7, 20, 20, false),
    ]
    .into_iter()
    .filter(|&(kind, _, _, _)| operational(city, kind))
    .map(|(kind, radius, strength, commerce)| (site(city, kind).expect("active reward"), radius, strength, commerce))
    .collect()
}

/// The strongest nearby landmark wins. No stacking or accumulation on old maps.
pub fn land_bonus(fields: &[(Rect2i, i64, i64, bool)], x: i64, y: i64, zone: i64) -> i64 {
    fields
        .iter()
        .map(|&(site, radius, strength, commerce)| {
            if commerce && !matches!(zone, 3 | 4) {
                return 0;
            }
            let dx = (site.position.x - x).max(0).max(x - site.position.x - site.size.x + 1);
            let dy = (site.position.y - y).max(0).max(y - site.position.y - site.size.y + 1);
            let distance = dx.max(dy);
            let bonus = strength * (radius - distance).max(0) / radius;
            if matches!(zone, 5 | 6) { 0 } else { bonus }
        })
        .max()
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn city() -> City {
        let mut city = super::super::testing::empty_city(32);
        city.set_funds(1_000_000);
        write_u32_be(city.misc.mutate(), misc::NORMAL_POPULATION, 150_000);
        enable(&mut city);
        city
    }
    #[test]
    fn classic_is_unchanged_and_locked_buildings_cannot_be_forced() {
        let mut c = super::super::testing::empty_city(32);
        let before = c.clone();
        unlock(&mut c);
        monthly(&mut c);
        reconcile(&mut c);
        assert_eq!(c.misc.data, before.misc.data);
        assert!(!c.xexp.present);
        assert!(!place(&mut c, 0, Vec2i::new(10, 10), 1, 1).base.ok);
        assert_eq!(c.xbld.data, before.xbld.data);
        enable(&mut c);
        assert!(!place(&mut c, 7, Vec2i::new(10, 10), 1, 1).base.ok);
    }
    #[test]
    fn upkeep_is_once_per_month_and_benefits_require_payment_and_power() {
        let mut c = city();
        assert!(place(&mut c, 0, Vec2i::new(10, 10), 1, 1).base.ok);
        assert!(!operational(&c, 0));
        let n = indices(&c, site(&c, 0).unwrap())[0] as usize;
        c.xbit.mutate()[n] |= flags::POWERED as u8;
        assert!(operational(&c, 0));
        let funds = c.funds();
        c.set_misc_u32(misc::CITY_DAYS, 25);
        monthly(&mut c);
        assert_eq!(c.funds(), funds - 10);
        monthly(&mut c);
        assert_eq!(c.funds(), funds - 10);
        c.set_funds(9);
        c.set_misc_u32(misc::CITY_DAYS, 50);
        monthly(&mut c);
        assert_eq!(c.funds(), 9);
        assert!(!operational(&c, 0));
        assert!(influences(&c).is_empty());
        c.set_funds(10);
        c.set_misc_u32(misc::CITY_DAYS, 75);
        monthly(&mut c);
        assert!(operational(&c, 0));
    }
    #[test]
    fn boundaries_occupied_sites_and_invalid_extension_are_rejected() {
        let mut c = city();
        let before = c.xbld.data.clone();
        assert!(!preview(&c, 0, Vec2i::new(0, 0)).is_empty());
        assert!(!preview(&c, 0, Vec2i::new(31, 31)).is_empty());
        c.xbld.mutate()[10 * 32 + 10] = 1;
        assert!(!place(&mut c, 0, Vec2i::new(10, 10), 1, 1).base.ok);
        c.xbld.replace(before);
        c.xexp.mutate()[0] = 0;
        assert!(validate(&c).is_err());
    }
    #[test]
    fn landmarks_do_not_stack_or_benefit_industry() {
        let parcel = Rect2i::from(Vec2i::new(10, 10), Vec2i::new(4, 4));
        let field = (parcel, 10, 8, false);
        assert_eq!(land_bonus(&[field, field], 10, 10, 1), 8);
        assert_eq!(land_bonus(&[field], 23, 10, 1), 0);
        assert_eq!(land_bonus(&[field], 10, 10, 6), 0);
        assert_eq!(land_bonus(&[(parcel, 10, 16, true)], 10, 10, 1), 0);
        assert_eq!(land_bonus(&[(parcel, 10, 16, true)], 10, 10, 3), 16);
    }
    #[test]
    fn rotation_and_damage_keep_ownership_consistent() {
        let mut c = city();
        assert!(place(&mut c, 0, Vec2i::new(10, 10), 1, 1).base.ok);
        let original = c.xexp.data.clone();
        for _ in 0..4 {
            super::super::tools::rotation::rotate(&mut c, false);
            assert!(validate(&c).is_ok());
        }
        assert_eq!(original, c.xexp.data);
        let n = indices(&c, site(&c, 0).unwrap())[0] as usize;
        c.xbld.mutate()[n] = 1;
        reconcile(&mut c);
        assert!(available(&c, 0));
        assert_eq!(c.xbld.data[n], 1);
        assert_eq!(c.xbld.data.iter().filter(|&&b| b == CARRIER).count(), 0);
    }
    #[test]
    fn local_population_includes_arcologies_and_unlocks_persist() {
        let mut c = city();
        assert!(available(&c, 0));
        assert!(!available(&c, 7));
        write_u32_be(c.misc.mutate(), misc::ARCOLOGY_POPULATION, 4_000_000);
        unlock(&mut c);
        write_u32_be(c.misc.mutate(), misc::NORMAL_POPULATION, 0);
        write_u32_be(c.misc.mutate(), misc::ARCOLOGY_POPULATION, 0);
        unlock(&mut c);
        assert!(available(&c, 7));
    }
    #[test]
    fn large_building_occupies_every_cell_and_rebuilds_without_reward_flag_changes() {
        let mut c = city();
        write_u32_be(c.misc.mutate(), misc::ARCOLOGY_POPULATION, 4_000_000);
        let rewards = c.misc_u32(misc::GRANTED_REWARDS);
        let r = place(&mut c, 7, Vec2i::new(12, 12), 3, 4);
        assert!(r.base.ok, "{}", r.base.error);
        assert_eq!(r.base.tile_indices.0.len(), 36);
        assert!(!available(&c, 7));
        assert!(validate(&c).is_ok());
        assert!(!place(&mut c, 7, Vec2i::new(20, 20), 3, 4).base.ok);
        remove(&mut c, 7);
        assert!(available(&c, 7));
        assert_eq!(c.misc_u32(misc::GRANTED_REWARDS), rewards);
        assert!(c.xbld.data.iter().all(|&b| b == 0));
    }
}

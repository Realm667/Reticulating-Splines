//! Expanded facility upgrades. XUPG holds identities, finished levels and timed work.
//! Original map tiles and microsimulation records remain the building's source of truth.
use super::bytes::{read_u32_be, write_u32_be};
use super::city::City;
use super::geom::{Rect2i, Vec2i};
use super::ids::{building_tile_ids as tiles, sc2budget_layout as budget, sc2misc_layout as misc};
use super::tools::commands::{EditBase, building::BuildingResult};
use super::tools::demolish::{building_area, find_building_site};
use super::value::Ints32;
use std::collections::BTreeMap;

pub const FEATURE: &str = "rs.upgrades.v1";
pub const HEADER: usize = 24;
pub const RECORD: usize = 40;

#[derive(Clone, Copy, Debug)]
pub struct Site {
    pub offset: usize,
    pub id: i64,
    pub rect: Rect2i,
    pub tile: i64,
    pub level: i64,
    pub target: i64,
    pub finish: i64,
    pub paid: bool,
}

pub fn cost(tile: i64) -> i64 {
    match tile {
        tiles::HYDRO_POWER_1 | tiles::HYDRO_POWER_2 => 400,
        tiles::GAS_POWER => 2000,
        tiles::OIL_POWER => 6600,
        tiles::COAL_POWER => 4000,
        tiles::NUCLEAR_POWER => 15000,
        tiles::SOLAR_POWER => 1300,
        tiles::MICROWAVE_POWER => 28000,
        tiles::FUSION_POWER => 40000,
        tiles::POLICE_STATION | tiles::FIRE_STATION | tiles::HOSPITAL | tiles::LIBRARY => 500,
        tiles::SCHOOL | tiles::BUS_DEPOT | tiles::SUBWAY_STATION | tiles::WATER_TOWER => 250,
        tiles::COLLEGE | tiles::MUSEUM | tiles::DESALINIZATION => 1000,
        tiles::PRISON | tiles::ZOO => 3000,
        tiles::STADIUM => 5000,
        tiles::RAIL_STATION | tiles::WATER_TREATMENT => 500,
        _ => 0,
    }
}

pub fn valid_header(data: &[u8]) -> bool {
    data.len() >= HEADER && (data.len() - HEADER).is_multiple_of(RECORD) && &data[..4] == b"UPG1"
}

pub fn records(data: &[u8]) -> Vec<Site> {
    if !valid_header(data) {
        return Vec::new();
    }
    (HEADER..data.len())
        .step_by(RECORD)
        .map(|offset| {
            let read = |n| read_u32_be(data, (offset + n) as i64);
            let tile = read(12);
            Site {
                offset,
                id: read(0),
                rect: Rect2i::from(Vec2i::new(read(4), read(8)), Vec2i::new(building_area(tile), building_area(tile))),
                tile,
                level: read(16),
                target: read(20),
                finish: read(24),
                paid: read(28) != 0,
            }
        })
        .collect()
}

pub fn at(data: &[u8], point: Vec2i) -> Option<Site> {
    records(data).into_iter().find(|r| contains(r.rect, point))
}

fn contains(rect: Rect2i, p: Vec2i) -> bool {
    p.x >= rect.position.x && p.y >= rect.position.y && p.x < rect.position.x + rect.size.x && p.y < rect.position.y + rect.size.y
}

pub fn parcel(city: &City, point: Vec2i) -> Option<(i64, Rect2i)> {
    let index = city.index_of(point.x, point.y);
    if index < 0 {
        return None;
    }
    let tile = city.xbld.data[index as usize] as i64;
    if cost(tile) == 0 {
        return None;
    }
    let area = building_area(tile);
    let rect = if area == 1 {
        Rect2i::from(point, Vec2i::new(1, 1))
    } else {
        find_building_site(
            &city.xbld.data,
            &city.xzon.data,
            point,
            tile,
            area,
            city.compass_rotation(),
            city.map_size,
        )
    };
    if rect.size.x != area
        || rect.size.y != area
        || super::expanded::indices(city, rect).len() != (area * area) as usize
        || super::expanded::indices(city, rect)
            .iter()
            .any(|&i| city.xbld.data[i as usize] as i64 != tile)
    {
        return None;
    }
    Some((tile, rect))
}

fn facility(city: &City, rect: Rect2i) -> i64 {
    super::expanded::indices(city, rect)
        .into_iter()
        .find_map(|i| {
            let id = if super::overlay::is_layered(&city.xtxt.data) {
                super::overlay::facility(&city.xtxt.data, i)
            } else {
                super::overlay::read(&city.xtxt.data, i)
            };
            super::overlay::is_facility(id).then_some(id)
        })
        .unwrap_or(0)
}

fn matches(city: &City, site: Site) -> bool {
    parcel(city, site.rect.position).is_some_and(|(tile, rect)| tile == site.tile && rect == site.rect)
        && facility(city, site.rect) == read_u32_be(&city.xupg.data, (site.offset + 36) as i64)
}

pub fn validate(city: &City) -> Result<(), String> {
    if !city.xupg.present {
        return Ok(());
    }
    if !super::expanded::enabled(city) || !valid_header(&city.xupg.data) {
        return Err("Invalid building upgrade data.".into());
    }
    let mut seen = std::collections::HashSet::new();
    let mut identities = std::collections::HashSet::new();
    for r in records(&city.xupg.data) {
        if r.id == 0
            || !identities.insert(r.id)
            || r.id > read_u32_be(&city.xupg.data, 4)
            || r.level > 2
            || (r.level == 0 && r.target == 0)
            || (r.target == 0 && r.finish != 0)
            || read_u32_be(&city.xupg.data, (r.offset + 28) as i64) > 1
            || read_u32_be(&city.xupg.data, (r.offset + 32) as i64) >= 12000
            || !(r.target == 0 || r.target == r.level + 1 && r.target <= 2)
            || !matches(city, r)
            || super::expanded::indices(city, r.rect).iter().any(|i| !seen.insert(*i))
        {
            return Err("Invalid building upgrade identity.".into());
        }
    }
    Ok(())
}

pub fn unlocked(city: &City, level: i64) -> bool {
    let population = read_u32_be(&city.xexp.data, 4).max(city.misc_u32(misc::NORMAL_POPULATION) + city.misc_u32(misc::ARCOLOGY_POPULATION));
    let year = city.misc_u32(misc::START_YEAR) + city.age_in_days() / 300;
    super::expanded::enabled(city)
        && match level {
            1 => population >= 25000 && year >= 1920,
            2 => population >= 100000 && year >= 1950,
            _ => false,
        }
}

pub fn apply(city: &mut City, point: Vec2i, expected: i64, expected_level: i64) -> BuildingResult {
    let Some((tile, rect)) = parcel(city, point) else {
        return BuildingResult::rejected("This building cannot be upgraded.", 0);
    };
    if !valid_header(&city.xupg.data) || !super::expanded::enabled(city) {
        return BuildingResult::rejected("Building upgrades require Expanded rules.", 0);
    }
    let old = at(&city.xupg.data, point);
    let level = old.map_or(0, |r| r.level);
    if old.map_or(0, |r| r.id) != expected || level != expected_level || old.is_some_and(|r| r.target != 0 || !matches(city, r)) {
        return BuildingResult::rejected("The building changed. Reopen its query.", 0);
    }
    if !unlocked(city, level + 1) {
        return BuildingResult::rejected("This upgrade is not unlocked.", 0);
    }
    let price = (cost(tile) * if level == 0 { 175 } else { 250 } + 99) / 100;
    if city.funds() < price {
        return BuildingResult::rejected("Insufficient funds.", 0);
    }
    let offset = if let Some(r) = old {
        r.offset
    } else {
        let offset = city.xupg.data.len();
        let next = read_u32_be(&city.xupg.data, 4) + 1;
        if next > u32::MAX as i64 {
            return BuildingResult::rejected("Invalid building upgrade identity.", 0);
        }
        let id = facility(city, rect);
        city.xupg.mutate().resize(offset + RECORD, 0);
        for (n, value) in [(0, next), (4, rect.position.x), (8, rect.position.y), (12, tile), (28, 1), (36, id)] {
            write_u32_be(city.xupg.mutate(), (offset + n) as i64, value);
        }
        write_u32_be(city.xupg.mutate(), 4, next);
        offset
    };
    let finish = city.age_in_days() + if level == 0 { 75 } else { 150 };
    write_u32_be(city.xupg.mutate(), (offset + 20) as i64, level + 1);
    write_u32_be(city.xupg.mutate(), (offset + 24) as i64, finish);
    city.set_funds(city.funds() - price);
    let mut result = BuildingResult {
        base: EditBase::accepted("upgrade", -1, -1),
        ..Default::default()
    };
    result.base.site = rect;
    result.base.tile_indices = Ints32(super::expanded::indices(city, rect).iter().map(|&n| n as i32).collect());
    result.base.cost = price;
    result.base.listed_cost = price;
    result.tile_id = tile;
    result
}

pub fn reconcile(city: &mut City) {
    if !valid_header(&city.xupg.data) {
        return;
    }
    let mut data = city.xupg.data[..HEADER].to_vec();
    for r in records(&city.xupg.data) {
        if matches(city, r) {
            data.extend_from_slice(&city.xupg.data[r.offset..r.offset + RECORD]);
        }
    }
    if data != city.xupg.data {
        city.xupg.replace(data);
    }
}

pub fn remove_at(city: &mut City, point: Vec2i) {
    if let Some(r) = at(&city.xupg.data, point) {
        city.xupg.mutate().drain(r.offset..r.offset + RECORD);
    }
}

/// Annual base upkeep, in thousandths of a dollar, and its original funding control.
pub fn upkeep(tile: i64) -> (i64, i64) {
    match tile {
        tiles::POLICE_STATION => (100000, budget::POLICE),
        tiles::FIRE_STATION => (100000, budget::FIRE),
        tiles::HOSPITAL => (50000, budget::HEALTH),
        tiles::SCHOOL => (25000, budget::SCHOOL),
        tiles::COLLEGE => (100000, budget::COLLEGE),
        tiles::BUS_DEPOT => (25000, budget::ROAD),
        tiles::RAIL_STATION => (1600, budget::RAIL),
        tiles::SUBWAY_STATION => (400, budget::SUBWAY),
        _ => (0, -1),
    }
}

pub fn annual_extra(city: &City, tile: i64, level: i64) -> i64 {
    let (base, control) = upkeep(tile);
    let funding = if control < 0 {
        100
    } else {
        city.misc_i32(misc::BUDGETS + control * budget::RECORD_SIZE + budget::FUNDING)
            .clamp(0, 100)
    };
    base * level * funding / 200
}

pub fn advance(city: &mut City) {
    reconcile(city);
    if !valid_header(&city.xupg.data) {
        return;
    }
    let day = city.age_in_days();
    let month = day / 25;
    let previous = read_u32_be(&city.xupg.data, 8);
    let mut charged = 0;
    if read_u32_be(&city.xupg.data, 20) != day / 300 {
        write_u32_be(city.xupg.mutate(), 16, 0);
        write_u32_be(city.xupg.mutate(), 20, day / 300);
    }
    // Bill the already completed level. A completion starts its new rate next month.
    if month > previous {
        for r in records(&city.xupg.data) {
            let amount = annual_extra(city, r.tile, r.level) * (month - previous) + read_u32_be(&city.xupg.data, (r.offset + 32) as i64);
            let cost = amount / 12000;
            let paid = cost == 0 || city.funds() >= cost;
            if paid {
                city.set_funds(city.funds() - cost);
                charged += cost;
            }
            write_u32_be(city.xupg.mutate(), (r.offset + 28) as i64, i64::from(paid));
            write_u32_be(city.xupg.mutate(), (r.offset + 32) as i64, amount % 12000);
        }
        write_u32_be(city.xupg.mutate(), 8, month);
        write_u32_be(city.xupg.mutate(), 12, charged);
        let ytd = read_u32_be(&city.xupg.data, 16) + charged;
        write_u32_be(city.xupg.mutate(), 16, ytd);
    }
    for r in records(&city.xupg.data) {
        if r.target != 0 && day >= r.finish {
            if r.tile == tiles::WATER_TOWER {
                for i in super::expanded::indices(city, r.rect) {
                    city.xbit.mutate()[i as usize] &= !(super::ids::sc2tile_flags::WATERED as u8);
                }
            }
            write_u32_be(city.xupg.mutate(), (r.offset + 16) as i64, r.target);
            write_u32_be(city.xupg.mutate(), (r.offset + 20) as i64, 0);
            write_u32_be(city.xupg.mutate(), (r.offset + 24) as i64, 0);
        }
    }
}

pub fn levels(city: &City) -> BTreeMap<i64, i64> {
    let mut levels = BTreeMap::new();
    for r in records(&city.xupg.data) {
        if r.paid && r.level > 0 {
            for i in super::expanded::indices(city, r.rect) {
                levels.insert(i, r.level);
            }
        }
    }
    levels
}

pub fn extra_units(city: &City, tile: i64, units_per_building: i64) -> i64 {
    records(&city.xupg.data)
        .iter()
        .filter(|r| r.tile == tile && r.paid)
        .map(|r| r.level * units_per_building)
        .sum::<i64>()
        / 2
}

pub fn rotate(city: &mut City, clockwise: bool) {
    for r in records(&city.xupg.data) {
        let p = r.rect.position;
        let area = r.rect.size.x;
        let (x, y) = if clockwise {
            (city.map_size - p.y - area, p.x)
        } else {
            (p.y, city.map_size - p.x - area)
        };
        write_u32_be(city.xupg.mutate(), (r.offset + 4) as i64, x);
        write_u32_be(city.xupg.mutate(), (r.offset + 8) as i64, y);
        // Rotation changes the directional hydro tile number.
        let i = city.index_of(x, y);
        if i >= 0 {
            let tile = city.xbld.data[i as usize] as i64;
            write_u32_be(city.xupg.mutate(), (r.offset + 12) as i64, tile);
        }
    }
}

/// No allocation on infrastructure and transit hot paths.
pub fn level_at(data: &[u8], point: Vec2i) -> i64 {
    if !valid_header(data) {
        return 0;
    }
    for r in data[HEADER..].chunks_exact(RECORD) {
        let area = building_area(read_u32_be(r, 12));
        let x = read_u32_be(r, 4);
        let y = read_u32_be(r, 8);
        if point.x >= x && point.x < x + area && point.y >= y && point.y < y + area {
            return if read_u32_be(r, 28) != 0 { read_u32_be(r, 16).min(2) } else { 0 };
        }
    }
    0
}

pub fn info(city: &City, point: Vec2i) -> super::value::Value {
    use super::value::{ToValue, Value};
    let Some((tile, rect)) = parcel(city, point).filter(|_| super::expanded::enabled(city)) else {
        return Value::Dict(vec![]);
    };
    let r = at(&city.xupg.data, point);
    let level = r.map_or(0, |r| r.level);
    let target = r.map_or(0, |r| r.target);
    let price = (cost(tile) * if level == 0 { 175 } else { 250 } + 99) / 100;
    let available = target == 0 && unlocked(city, level + 1) && city.funds() >= price;
    let facility_id = facility(city, rect);
    let life = if (tiles::GAS_POWER..=tiles::COAL_POWER).contains(&tile) && super::overlay::is_facility(facility_id) {
        let record = super::overlay::facility_record(facility_id) as usize;
        (50 - i64::from(*city.xmic.data.get(record * 8 + 1).unwrap_or(&0))).max(0)
    } else {
        -1
    };
    let mut values = vec![("site", rect.to_value()), ("available", available.to_value())];
    for (k, v) in [
        ("life", life),
        ("tile", tile),
        ("identity", r.map_or(0, |r| r.id)),
        ("level", level),
        ("target", target),
        ("remaining", r.map_or(0, |r| (r.finish - city.age_in_days()).max(0))),
        ("cost", price),
        ("upkeep", annual_extra(city, tile, 2 + level)),
        ("next_upkeep", annual_extra(city, tile, 3 + level)),
        ("days", if level == 0 { 75 } else { 150 }),
        ("paid", i64::from(r.is_none_or(|r| r.paid))),
    ] {
        values.push((k, v.to_value()));
    }
    Value::Dict(values.into_iter().map(|(k, v)| (Value::Str(k.into()), v)).collect())
}

pub fn budget_info(city: &City) -> super::value::Value {
    use super::value::{ToValue, Value};
    let annual = records(&city.xupg.data)
        .iter()
        .map(|r| annual_extra(city, r.tile, r.level))
        .sum::<i64>()
        / 1000;
    let ytd = if valid_header(&city.xupg.data) && read_u32_be(&city.xupg.data, 20) == city.age_in_days() / 300 {
        read_u32_be(&city.xupg.data, 16)
    } else {
        0
    };
    let month = city.age_in_days() / 25;
    let end = (month / 12 + 1) * 12;
    let mut remaining = 0;
    for record in records(&city.xupg.data) {
        let mut carry = read_u32_be(&city.xupg.data, (record.offset + 32) as i64);
        for future in month + 1..end {
            let level = if record.target > 0 && record.finish < future * 25 {
                record.target
            } else {
                record.level
            };
            carry += annual_extra(city, record.tile, level);
            remaining += carry / 12000;
            carry %= 12000;
        }
    }
    Value::Dict(
        [
            ("annual", annual),
            ("ytd", ytd),
            ("remaining", remaining),
            ("estimated", ytd + remaining),
        ]
        .into_iter()
        .map(|(k, v)| (Value::Str(k.into()), v.to_value()))
        .collect(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sim::{city::Chunk, infrastructure, random::SimRandom, testing, tools};
    fn fixture(tile: i64) -> City {
        let mut c = testing::empty_sc2x_city(64);
        c.set_funds(1_000_000);
        c.set_misc_u32(misc::NORMAL_POPULATION, 100000);
        c.set_misc_u32(misc::START_YEAR, 1950);
        super::super::expanded::enable(&mut c);
        let mut data = vec![0; HEADER];
        data[..4].copy_from_slice(b"UPG1");
        c.xupg = Chunk::new(data);
        let area = building_area(tile);
        let p = Vec2i::new(10, 10);
        for x in 10..10 + area {
            for y in 10..10 + area {
                let i = c.index_of(x, y) as usize;
                c.xbld.data[i] = tile as u8;
                c.xbit.data[i] = crate::sim::ids::sc2tile_flags::POWERABLE as u8;
            }
        }
        tools::set_corners(&mut c.xzon.data, p, area, 0, 64);
        c.set_misc_u32(misc::TILE_COUNTS + tile * 4, area * area);
        c
    }
    #[test]
    fn timing_identity_price_and_demolition() {
        let mut c = fixture(tiles::COAL_POWER);
        let p = Vec2i::new(10, 10);
        assert!(validate(&c).is_ok());
        assert!(apply(&mut c, p, 0, 0).base.ok);
        assert_eq!(c.funds(), 993000);
        let id = at(&c.xupg.data, p).unwrap().id;
        assert!(!apply(&mut c, p, 0, 0).base.ok);
        assert!(!apply(&mut c, p, id, 0).base.ok);
        c.set_misc_u32(misc::CITY_DAYS, 74);
        advance(&mut c);
        assert_eq!(level_at(&c.xupg.data, p), 0);
        c.set_misc_u32(misc::CITY_DAYS, 75);
        advance(&mut c);
        assert_eq!(level_at(&c.xupg.data, p), 1);
        assert!(apply(&mut c, p, id, 1).base.ok);
        assert_eq!(c.funds(), 983000);
        c.set_misc_u32(misc::CITY_DAYS, 224);
        advance(&mut c);
        assert_eq!(level_at(&c.xupg.data, p), 1);
        c.set_misc_u32(misc::CITY_DAYS, 225);
        advance(&mut c);
        assert_eq!(level_at(&c.xupg.data, p), 2);
        assert!(!apply(&mut c, p, id, 2).base.ok);
        let index = c.index_of(10, 10) as usize;
        c.xbld.data[index] = 0;
        reconcile(&mut c);
        assert!(records(&c.xupg.data).is_empty());
        assert_eq!(c.funds(), 983000);
        c.xbld.data[index] = tiles::COAL_POWER as u8;
        assert!(apply(&mut c, p, 0, 0).base.ok);
        assert_ne!(at(&c.xupg.data, p).unwrap().id, id);
    }
    #[test]
    fn classic_and_unlock_and_insufficient_funds_do_not_mutate() {
        let p = Vec2i::new(10, 10);
        let mut c = fixture(tiles::HOSPITAL);
        c.xexp = Chunk::default();
        let before = c.clone();
        assert!(!apply(&mut c, p, 0, 0).base.ok);
        assert_eq!(c.misc.data, before.misc.data);
        assert_eq!(c.xupg.data, before.xupg.data);
        super::super::expanded::enable(&mut c);
        c.set_misc_u32(misc::START_YEAR, 1900);
        assert!(!apply(&mut c, p, 0, 0).base.ok);
        c.set_misc_u32(misc::START_YEAR, 1950);
        c.set_funds(874);
        assert!(!apply(&mut c, p, 0, 0).base.ok);
        c.set_funds(875);
        assert!(apply(&mut c, p, 0, 0).base.ok);
        assert_eq!(c.funds(), 0);
    }
    #[test]
    fn classic_budget_has_zero_upgrade_costs_without_a_chunk() {
        use crate::sim::value::Value;
        let c = testing::empty_sc2x_city(64);
        assert!(!c.xupg.present);
        let Value::Dict(values) = budget_info(&c) else {
            panic!("budget dictionary")
        };
        assert_eq!(values.len(), 4);
        assert!(values.iter().all(|(_, value)| *value == Value::Int(0)));
    }
    #[test]
    fn power_output_and_rng_are_preserved_until_completion() {
        let p = Vec2i::new(10, 10);
        let mut c = fixture(tiles::COAL_POWER);
        let mut rng = SimRandom::new(31);
        let original = infrastructure::power::run(&mut c, &mut rng).generation;
        assert_eq!(original, 704);
        assert!(apply(&mut c, p, 0, 0).base.ok);
        assert_eq!(infrastructure::power::run(&mut c, &mut rng).generation, original);
        c.set_misc_u32(misc::CITY_DAYS, 75);
        advance(&mut c);
        assert_eq!(infrastructure::power::run(&mut c, &mut rng).generation, original * 3 / 2);
        assert_eq!(rng.state, 31);
    }
    #[test]
    fn monthly_fractional_upkeep_funding_and_nonpayment() {
        let mut c = fixture(tiles::POLICE_STATION);
        let p = Vec2i::new(10, 10);
        c.set_misc_u32(misc::BUDGETS + budget::POLICE * budget::RECORD_SIZE + budget::FUNDING, 100);
        assert!(apply(&mut c, p, 0, 0).base.ok);
        c.set_misc_u32(misc::CITY_DAYS, 75);
        advance(&mut c);
        let funds = c.funds();
        for month in 4..16 {
            c.set_misc_u32(misc::CITY_DAYS, month * 25);
            advance(&mut c);
            advance(&mut c);
        }
        assert_eq!(c.funds(), funds - 50);
        c.set_funds(0);
        c.set_misc_u32(misc::CITY_DAYS, 400);
        advance(&mut c);
        assert_eq!(level_at(&c.xupg.data, p), 0);
        c.set_funds(100);
        c.set_misc_u32(misc::CITY_DAYS, 425);
        advance(&mut c);
        assert_eq!(level_at(&c.xupg.data, p), 1);
        assert_eq!(annual_extra(&c, tiles::POLICE_STATION, 1), 50000);
        c.set_misc_u32(misc::BUDGETS + budget::POLICE * budget::RECORD_SIZE + budget::FUNDING, 50);
        assert_eq!(annual_extra(&c, tiles::POLICE_STATION, 1), 25000);
        assert_eq!(annual_extra(&c, tiles::COAL_POWER, 2), 0);
        let mut free_operation = fixture(tiles::COAL_POWER);
        assert!(apply(&mut free_operation, p, 0, 0).base.ok);
        free_operation.set_funds(-100);
        free_operation.set_misc_u32(misc::CITY_DAYS, 75);
        advance(&mut free_operation);
        free_operation.set_misc_u32(misc::CITY_DAYS, 100);
        advance(&mut free_operation);
        assert_eq!(level_at(&free_operation.xupg.data, p), 1);
        assert_eq!(free_operation.funds(), -100);
    }
    #[test]
    fn budget_forecast_matches_construction_and_fractional_monthly_payments() {
        use crate::sim::value::Value;
        let mut c = fixture(tiles::POLICE_STATION);
        let p = Vec2i::new(10, 10);
        c.set_misc_u32(misc::BUDGETS + budget::POLICE * budget::RECORD_SIZE + budget::FUNDING, 100);
        assert!(apply(&mut c, p, 0, 0).base.ok);
        let estimated = |city: &City| {
            let Value::Dict(values) = budget_info(city) else {
                panic!("budget dictionary")
            };
            values
                .into_iter()
                .find(|(key, _)| *key == Value::Str("estimated".into()))
                .unwrap()
                .1
        };
        assert_eq!(estimated(&c), Value::Int(33));
        for day in 1..=100 {
            c.set_misc_u32(misc::CITY_DAYS, day);
            advance(&mut c);
        }
        assert_eq!(estimated(&c), Value::Int(33));
        let id = at(&c.xupg.data, p).unwrap().id;
        assert!(apply(&mut c, p, id, 1).base.ok);
        let forecast = estimated(&c);
        assert_eq!(forecast, Value::Int(37));
        for day in 101..300 {
            c.set_misc_u32(misc::CITY_DAYS, day);
            advance(&mut c);
        }
        assert_eq!(Value::Int(read_u32_be(&c.xupg.data, 16)), forecast);
    }
    #[test]
    fn upgraded_prison_handles_more_inmates_without_overcrowding() {
        use crate::sim::{bytes::write_u16_be, civic::annual, overlay};
        let mut c = fixture(tiles::PRISON);
        let p = Vec2i::new(10, 10);
        let i = c.index_of(p.x, p.y);
        overlay::write(&mut c.xtxt.data, i, overlay::facility_id(1));
        c.xmic.data[8] = tiles::PRISON as u8;
        c.set_misc_u32(misc::BUDGETS + budget::POLICE * budget::RECORD_SIZE + budget::FUNDING, 100);
        c.set_misc_u32(misc::OLD_ARRESTS, 12000);
        write_u16_be(&mut c.xmic.data, 10, 0);
        assert!(apply(&mut c, p, 0, 0).base.ok);
        c.set_misc_u32(misc::CITY_DAYS, 75);
        advance(&mut c);
        let mut original = c.clone();
        original.xupg = Chunk::default();
        let mut rng = SimRandom::new(31);
        let mut old_rng = SimRandom::new(31);
        fn run(city: &mut City, random: &mut SimRandom) {
            let mut inputs = annual::AnnualInputs {
                bus_passengers: 0,
                rail_passengers: 0,
                subway_passengers: 0,
                random: Some(random),
                lfsr: None,
                game: None,
                power_usage_percent: 0,
                water_usage_percent: 0,
                australian_locale: false,
                mayor_approval: 50,
                stage_launch: false,
            };
            annual::run(city, &mut inputs);
        }
        run(&mut c, &mut rng);
        run(&mut original, &mut old_rng);
        assert_eq!(crate::sim::bytes::read_u16_be(&c.xmic.data, 14), 120);
        assert_eq!(c.xmic.data[9], 0);
        assert!(crate::sim::bytes::read_u16_be(&original.xmic.data, 14) < 120);
        assert_eq!(rng.state, 31);
        assert_ne!(old_rng.state, 31);
    }
    #[test]
    fn rotation_and_malformed_records() {
        let mut c = fixture(tiles::SCHOOL);
        assert!(apply(&mut c, Vec2i::new(10, 10), 0, 0).base.ok);
        let initial = c.xupg.data.clone();
        for _ in 0..4 {
            crate::sim::tools::rotation::rotate(&mut c, false);
            assert!(validate(&c).is_ok());
        }
        assert_eq!(initial, c.xupg.data);
        let record = c.xupg.data[HEADER..].to_vec();
        c.xupg.data.extend(record);
        assert!(validate(&c).is_err());
    }
    #[test]
    fn education_and_local_services_use_completed_levels() {
        use crate::sim::{civic::education, data_maps::native, ids::sc2tile_flags as flags};
        let p = Vec2i::new(10, 10);
        for (tile, control, expected) in [
            (tiles::HOSPITAL, budget::HEALTH, [37, 0, 0]),
            (tiles::SCHOOL, budget::SCHOOL, [0, 22, 0]),
            (tiles::COLLEGE, budget::COLLEGE, [0, 0, 75]),
            (tiles::LIBRARY, budget::SCHOOL, [0, 5, 0]),
            (tiles::MUSEUM, budget::COLLEGE, [0, 0, 5]),
        ] {
            let mut c = fixture(tile);
            c.set_misc_u32(misc::BUDGETS + control * budget::RECORD_SIZE + budget::FUNDING, 100);
            assert!(apply(&mut c, p, 0, 0).base.ok);
            c.set_misc_u32(misc::CITY_DAYS, 75);
            advance(&mut c);
            let result = education::run(&mut c, &mut SimRandom::new(31));
            assert_eq!([result.health_capacity, result.school_capacity, result.college_capacity], expected);
            c.set_misc_u32(misc::BUDGETS + control * budget::RECORD_SIZE + budget::FUNDING, 0);
            let result = education::run(&mut c, &mut SimRandom::new(31));
            assert_eq!([result.health_capacity, result.school_capacity, result.college_capacity], [0, 0, 0]);
        }
        for (tile, control, chunk) in [
            (tiles::POLICE_STATION, budget::POLICE, "XPLC"),
            (tiles::FIRE_STATION, budget::FIRE, "XFIR"),
        ] {
            let mut c = fixture(tile);
            c.set_misc_u32(misc::BUDGETS + control * budget::RECORD_SIZE + budget::FUNDING, 100);
            for index in super::super::expanded::indices(&c, parcel(&c, p).unwrap().1) {
                c.xbit.data[index as usize] |= flags::POWERED as u8;
            }
            native::run_pollution_and_coverage(&mut c);
            let original = c.chunk(chunk).unwrap().data.clone();
            assert!(apply(&mut c, p, 0, 0).base.ok);
            c.set_misc_u32(misc::CITY_DAYS, 75);
            advance(&mut c);
            native::run_pollution_and_coverage(&mut c);
            let upgraded = &c.chunk(chunk).unwrap().data;
            assert!(original.iter().zip(upgraded).all(|(a, b)| b >= a));
            assert!(original.iter().zip(upgraded).any(|(a, b)| b > a));
        }
    }
    #[test]
    fn water_treatment_storage_and_transit_have_real_effects() {
        use crate::sim::{ids::sc2tile_flags as flags, trip};
        let p = Vec2i::new(10, 10);
        let mut c = fixture(tiles::WATER_TREATMENT);
        assert_eq!(infrastructure::water::run(&mut c).treatment_capacity, 2000);
        assert!(apply(&mut c, p, 0, 0).base.ok);
        c.set_misc_u32(misc::CITY_DAYS, 75);
        advance(&mut c);
        assert_eq!(infrastructure::water::run(&mut c).treatment_capacity, 3000);
        let mut c = fixture(tiles::WATER_TOWER);
        assert!(apply(&mut c, p, 0, 0).base.ok);
        c.set_misc_u32(misc::CITY_DAYS, 75);
        advance(&mut c);
        let area = building_area(tiles::WATER_TOWER);
        for x in 10..10 + area {
            for y in 10..10 + area {
                let i = c.index_of(x, y) as usize;
                c.xbit.data[i] = (flags::POWERED | flags::PIPED | flags::WATERED) as u8;
            }
        }
        let i = c.index_of(9, 10) as usize;
        c.xbld.data[i] = tiles::WATER_PUMP as u8;
        c.xbit.data[i] = (flags::POWERED | flags::PIPED) as u8;
        assert_eq!(infrastructure::water::run(&mut c).supply, area * area * 150);
        for tile in [tiles::BUS_DEPOT, tiles::RAIL_STATION, tiles::SUBWAY_STATION] {
            let mut c = fixture(tile);
            assert!(apply(&mut c, p, 0, 0).base.ok);
            for (day, cost) in [(74, 4), (75, 3)] {
                c.set_misc_u32(misc::CITY_DAYS, day);
                advance(&mut c);
                let maps = trip::TripMaps {
                    upgrades: &c.xupg.data,
                    buildings: &c.xbld.data,
                    zones: &c.xzon.data,
                    underground: &c.xund.data,
                    text_overlays: &c.xtxt.data,
                    altitude: &c.altm.data,
                    map_edge: 64,
                };
                assert_eq!(
                    trip::advance(&maps, Vec2i::new(9, 10), p, 9 * 64 + 10, 10 * 64 + 10, trip::ROAD_MODE, 1) & 255,
                    cost
                );
            }
        }
    }
    #[test]
    fn completion_does_not_reset_plant_age_or_other_microsimulation_data() {
        let mut c = fixture(tiles::NUCLEAR_POWER);
        c.xmic.data[9] = 49;
        let before = c.xmic.data.clone();
        assert!(apply(&mut c, Vec2i::new(10, 10), 0, 0).base.ok);
        c.set_misc_u32(misc::CITY_DAYS, 75);
        advance(&mut c);
        assert_eq!(c.xmic.data, before);
        remove_at(&mut c, Vec2i::new(10, 10));
        assert!(records(&c.xupg.data).is_empty());
    }
}

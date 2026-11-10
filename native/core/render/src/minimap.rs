//! City Map window images: one palette index per tile, and the RGBA image of
//! those indices. Maps larger than 1024 tiles sample every second or fourth tile,
//! since the Map window never shows more than 1024 pixels.

use super::ids::underground_tile_ids as underground;
use super::ids::{building_tile_ids as tiles, sc2altitude_layout as altitude, sc2tile_flags as flags, sc2zone_layout as zone};

pub const MAX_IMAGE_EDGE: usize = 1024;

// Palette indices of the Map window.
const EMPTY_GROUND: u8 = 0x80;
const WATER_COLOR: u8 = 0x62;
const RUBBLE_COLOR: u8 = 0x35;
const TREE_COLOR: u8 = 0x43;
const DEVELOPED_COLOR: u8 = 0;
const HIGHLIGHT: u8 = 0xff;
const SUPPLIED: u8 = 0x32;
const CONNECTED: u8 = 0x1d;

/// The first of 15 gradient colors. A data value shows value >> 4 steps past it.
const GRADIENT_BASE: u8 = 0x9b;
const GRADIENT_SHIFT: u32 = 4;

/// Empty ground darkens by three quarters of a color step per altitude level, to this level.
const GROUND_ALTITUDE_LIMIT: i32 = 0x10;
// Growth values below LOW shrink, and values from HIGH grow.
const GROWTH_LOW: u8 = 0x7d;
const GROWTH_HIGH: u8 = 0x83;
const SHRINKING: u8 = 0x1d;
const GROWING: u8 = 0x43;

/// Colors of the zone types. Zone types above 6 use color 0.
const ZONE_COLORS: [u8; 16] = [0, 59, 59, 92, 92, 50, 50, 0, 0, 0, 0, 0, 0, 0, 0, 0];

/// The data maps of the Map window. Each mode names the chunk it reads.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mode {
    Structures,
    Zones,
    Roads,
    Rail,
    Traffic,
    Power,
    Water,
    Density,
    Growth,
    Crime,
    PolicePower,
    PoliceStations,
    Pollution,
    LandValue,
    FirePower,
    FireStations,
    Schools,
    Colleges,
}

impl Mode {
    /// Unknown names draw the structures map.
    pub fn from_name(name: &str) -> Self {
        match name {
            "zones" => Self::Zones,
            "roads" => Self::Roads,
            "rail" => Self::Rail,
            "traffic" => Self::Traffic,
            "power" => Self::Power,
            "water" => Self::Water,
            "density" => Self::Density,
            "growth" => Self::Growth,
            "crime" => Self::Crime,
            "police_power" => Self::PolicePower,
            "police_stations" => Self::PoliceStations,
            "pollution" => Self::Pollution,
            "land_value" => Self::LandValue,
            "fire_power" => Self::FirePower,
            "fire_stations" => Self::FireStations,
            "schools" => Self::Schools,
            "colleges" => Self::Colleges,
            _ => Self::Structures,
        }
    }

    /// The data chunk that the mode reads, if any.
    pub fn chunk(self) -> Option<&'static str> {
        Some(match self {
            Self::Traffic => "XTRF",
            Self::Density => "XPOP",
            Self::Growth => "XROG",
            Self::Crime => "XCRM",
            Self::PolicePower => "XPLC",
            Self::Pollution => "XPLT",
            Self::LandValue => "XVAL",
            Self::FirePower => "XFIR",
            _ => return None,
        })
    }
}

pub struct MinimapCity<'a> {
    pub edge: usize,
    pub buildings: &'a [u8],
    pub zones: &'a [u8],
    pub flags: &'a [u8],
    pub underground: &'a [u8],
    pub altitude: &'a [i32],
    /// The mode's data map at full, half or quarter resolution, or empty.
    pub data: &'a [u8],
    pub quarter: &'a [[i16; 4]],
}

impl MinimapCity<'_> {
    pub fn validate(&self) -> Result<(), String> {
        let cells = self.edge * self.edge;

        if self.edge == 0
            || [
                self.buildings.len(),
                self.zones.len(),
                self.flags.len(),
                self.underground.len(),
                self.altitude.len(),
            ]
            .iter()
            .any(|n| *n != cells)
        {
            return Err("invalid city map arrays".into());
        }
        if !self.quarter.is_empty() && (self.quarter.len() != cells || self.quarter.iter().flatten().any(|q| !(0..=128).contains(q))) {
            return Err("invalid minimap quarter heights".into());
        }

        Ok(())
    }

    // A legacy coarse grid covers two or four tiles per cell.
    fn data_value(&self, x: usize, y: usize) -> u8 {
        let edge = self.edge;
        let grid = [edge, edge / 2, edge / 4]
            .into_iter()
            .find(|g| *g > 0 && self.data.len() == g * g)
            .unwrap_or(0);
        if grid == 0 {
            return 0;
        }

        let scale = edge / grid;
        self.data[(x / scale) * grid + y / scale]
    }

    fn base(&self, i: usize, building: u8) -> u8 {
        if building == tiles::EMPTY {
            if self.flags[i] & flags::WATER != 0 {
                return WATER_COLOR;
            }

            if let Some(q) = self.quarter.get(i) {
                let mean = q.iter().map(|v| f32::from(*v)).sum::<f32>() / 16.0;
                return (f32::from(EMPTY_GROUND) - mean.clamp(0.0, 32.0) * 0.375).round() as u8;
            }
            let level = (self.altitude[i] & altitude::LAND_MASK).min(GROUND_ALTITUDE_LIMIT);

            return EMPTY_GROUND - (level * 3 / 4) as u8;
        }

        if building < tiles::TREES_1 {
            return RUBBLE_COLOR;
        }

        if building < tiles::SMALL_PARK {
            return TREE_COLOR;
        }

        DEVELOPED_COLOR
    }

    fn gradient_or(&self, x: usize, y: usize, base: u8) -> u8 {
        let gradient = self.data_value(x, y) >> GRADIENT_SHIFT;

        if gradient != 0 { gradient + GRADIENT_BASE } else { base }
    }

    /// The palette index of one tile. Tiles outside the map are 0.
    pub fn color_index(&self, x: usize, y: usize, mode: Mode) -> u8 {
        if x >= self.edge || y >= self.edge {
            return 0;
        }

        let i = x * self.edge + y;
        let b = self.buildings[i];
        let base = self.base(i, b);
        let tile_flags = self.flags[i];
        let marked = |hit: bool| if hit { HIGHLIGHT } else { base };

        match mode {
            Mode::Structures => base,
            Mode::Zones => {
                let zone = self.zones[i] & zone::TYPE_MASK;

                if zone != 0 { ZONE_COLORS[usize::from(zone)] } else { base }
            }
            Mode::Roads => marked(is_road(b)),
            Mode::Rail => marked(is_rail(b)),
            Mode::Traffic => {
                let traffic = self.data_value(x, y) >> GRADIENT_SHIFT;

                if traffic != 0 {
                    traffic + GRADIENT_BASE
                } else {
                    marked(is_traffic_network(b))
                }
            }
            Mode::Power => {
                if is_power_line(b) {
                    HIGHLIGHT
                } else if tile_flags & flags::POWERED != 0 {
                    SUPPLIED
                } else if tile_flags & flags::POWERABLE != 0 {
                    CONNECTED
                } else {
                    base
                }
            }
            Mode::Water => {
                if (underground::PIPE_LR..=underground::SUBWAY_ENTRANCE).contains(&self.underground[i]) {
                    HIGHLIGHT
                } else if tile_flags & flags::WATERED != 0 {
                    SUPPLIED
                } else if tile_flags & flags::PIPED != 0 {
                    CONNECTED
                } else {
                    base
                }
            }
            Mode::Growth => match self.data_value(x, y) {
                g if g < GROWTH_LOW => SHRINKING,
                g if g >= GROWTH_HIGH => GROWING,
                _ => base,
            },
            Mode::Density | Mode::Crime | Mode::PolicePower | Mode::Pollution | Mode::LandValue | Mode::FirePower => {
                self.gradient_or(x, y, base)
            }
            Mode::PoliceStations => marked(b == tiles::POLICE_STATION),
            Mode::FireStations => marked(b == tiles::FIRE_STATION),
            Mode::Schools => marked(b == tiles::SCHOOL),
            Mode::Colleges => marked(b == tiles::COLLEGE),
        }
    }
}

/// The image edge of a map: one pixel per tile up to 1024 tiles.
pub fn image_edge(edge: usize) -> usize {
    edge / (edge / MAX_IMAGE_EDGE).max(1)
}

/// Palette indices in image rows: the pixel at column x and row y shows tile
/// (x * step, y * step).
pub fn indices(city: &MinimapCity, mode: Mode) -> Vec<u8> {
    let size = image_edge(city.edge);
    let step = (city.edge / MAX_IMAGE_EDGE).max(1);
    let mut out = vec![0; size * size];

    for y in 0..size {
        for x in 0..size {
            out[y * size + x] = city.color_index(x * step, y * step, mode);
        }
    }

    out
}

/// RGBA8 pixels of the indices through a 256-entry RGBA palette.
pub fn colorize(indices: &[u8], palette: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(indices.len() * 4);

    for &index in indices {
        let at = usize::from(index) * 4;
        out.extend_from_slice(palette.get(at..at + 4).unwrap_or(&[0, 0, 0, 0]));
    }

    out
}

/// Fractional relief affects background terrain; network/service colors remain exact.
pub fn rgba(city: &MinimapCity, mode: Mode, palette: &[u8]) -> Vec<u8> {
    if city.quarter.is_empty() {
        return colorize(&indices(city, mode), palette);
    }
    let size = image_edge(city.edge);
    let step = (city.edge / MAX_IMAGE_EDGE).max(1);
    let mut out = Vec::with_capacity(size * size * 4);
    for y in 0..size {
        for x in 0..size {
            let (tx, ty) = (x * step, y * step);
            let i = tx * city.edge + ty;
            let index = city.color_index(tx, ty, mode);
            let fractional = city.buildings[i] == tiles::EMPTY && city.flags[i] & flags::WATER == 0 && index == city.base(i, tiles::EMPTY);
            if !fractional {
                let p = usize::from(index) * 4;
                out.extend_from_slice(palette.get(p..p + 4).unwrap_or(&[0, 0, 0, 0]));
                continue;
            }
            let mut sum = 0.0;
            let mut count = 0;
            for dx in 0..step {
                for dy in 0..step {
                    let cell = (tx + dx) * city.edge + ty + dy;
                    sum += city.quarter[cell].iter().map(|q| f32::from(*q)).sum::<f32>() / 16.0;
                    count += 1;
                }
            }
            // The full 0..32 terrain range uses the original terrain color ramp.
            let shade = f32::from(EMPTY_GROUND) - (sum / count as f32 / 2.0).clamp(0.0, 16.0) * 0.75;
            let first = shade.floor() as usize;
            let t = shade - first as f32;
            for c in 0..4 {
                let a = f32::from(*palette.get(first * 4 + c).unwrap_or(&0));
                let b = f32::from(*palette.get((first + 1) * 4 + c).unwrap_or(&0));
                out.push((a + (b - a) * t).round() as u8);
            }
        }
    }
    out
}

fn is_road(b: u8) -> bool {
    use tiles::*;
    matches!(b, ROAD_STRAIGHT_1..=ROAD_CROSSROADS
        | TUNNEL_ENTRANCE_1..=ROAD_RAIL_CROSSING_2
        | HIGHWAY_STRAIGHT_1..=RAISING_BRIDGE_OPEN
        | HIGHWAY_ONRAMP_1..=REINFORCED_HIGHWAY_BRIDGE)
}

fn is_rail(b: u8) -> bool {
    use tiles::*;
    matches!(b, RAIL_STRAIGHT_1..=RAIL_SLOPE_8
        | ROAD_RAIL_CROSSING_1..=RAIL_POWER_CROSSING_2
        | RAIL_SUBWAY_ENTRANCE_1..=RAIL_SUBWAY_ENTRANCE_4
        | HIGHWAY_RAIL_CROSSING_1
        | HIGHWAY_RAIL_CROSSING_2
        | RAIL_BRIDGE
        | RAIL_BRIDGE_PYLON)
}

fn is_traffic_network(b: u8) -> bool {
    use tiles::*;
    matches!(b, ROAD_STRAIGHT_1..=RAIL_SLOPE_8
        | TUNNEL_ENTRANCE_1..=RAIL_POWER_CROSSING_2
        | HIGHWAY_STRAIGHT_1..=HIGHWAY_POWER_CROSSING_2
        | HIGHWAY_ONRAMP_1..=RAIL_SUBWAY_ENTRANCE_4)
}

fn is_power_line(b: u8) -> bool {
    use tiles::*;
    matches!(
        b,
        POWER_LINE_STRAIGHT_1
            ..=POWER_LINE_CROSSROADS
                | ROAD_POWER_CROSSING_1
                | ROAD_POWER_CROSSING_2
                | RAIL_POWER_CROSSING_1
                | RAIL_POWER_CROSSING_2
                | POWER_BRIDGE
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ids::building_tile_ids::*;

    #[test]
    fn all_quarter_levels_use_the_full_range_and_keep_every_mode_classification() {
        let mut a = Arrays::new(1);
        let palette: Vec<u8> = (0..256_u16).flat_map(|i| [i as u8, i as u8, i as u8, 255]).collect();
        let mut last = 255;
        for q in 0..=128_i16 {
            let mut city = a.city();
            let corners = [[q; 4]];
            city.quarter = &corners;
            let image = rgba(&city, Mode::Structures, &palette);
            let expected = (128.0 - f32::from(q) / 8.0 * 0.75).round() as u8;
            assert_eq!(image, [expected, expected, expected, 255]);
            assert_eq!(city.color_index(0, 0, Mode::Structures), expected);
            assert!(image[0] <= last);
            last = image[0];
            assert!(city.validate().is_ok());
        }
        assert_eq!(last, 116);
        for name in [
            "structures",
            "zones",
            "roads",
            "rail",
            "traffic",
            "power",
            "water",
            "density",
            "growth",
            "crime",
            "police_power",
            "police_stations",
            "pollution",
            "land_value",
            "fire_power",
            "fire_stations",
            "schools",
            "colleges",
        ] {
            for building in 0..=255 {
                a.buildings[0] = building;
                for flag in 0..=255 {
                    a.flags[0] = flag;
                    let legacy = a.city();
                    let mode = Mode::from_name(name);
                    let index = legacy.color_index(0, 0, mode);
                    let q = [[127; 4]];
                    let mut city = a.city();
                    city.quarter = &q;
                    if index != legacy.base(0, building) {
                        assert_eq!(
                            rgba(&city, mode, &palette),
                            colorize(&[index], &palette),
                            "{name}, {building}, {flag}"
                        );
                    }
                }
            }
        }
    }

    #[test]
    fn downsampled_minimap_evaluates_all_corners_and_all_tiles_of_each_pixel() {
        let a = Arrays::new(2048);
        let mut q = vec![[0; 4]; 2048 * 2048];
        q[1] = [128; 4];
        q[2048] = [128; 4];
        let mut city = a.city();
        city.quarter = &q;
        let palette: Vec<u8> = (0..256_u16).flat_map(|i| [i as u8, i as u8, i as u8, 255]).collect();
        let image = rgba(&city, Mode::Structures, &palette);
        assert_eq!(&image[..4], &[122, 122, 122, 255]);
        assert_eq!(&image[4..8], &[128, 128, 128, 255]);
        let small = Arrays::new(1);
        for encoded in 0..9_usize.pow(4) {
            let corners = [std::array::from_fn(|k| ((encoded / 9_usize.pow(k as u32)) % 9) as i16)];
            let mut city = small.city();
            city.quarter = &corners;
            let mean = corners[0].iter().map(|q| f32::from(*q)).sum::<f32>() / 16.0;
            let expected = (128.0 - mean * 0.375).round() as u8;
            assert_eq!(&rgba(&city, Mode::Structures, &palette), &[expected, expected, expected, 255]);
        }
    }

    struct Arrays {
        edge: usize,
        buildings: Vec<u8>,
        zones: Vec<u8>,
        flags: Vec<u8>,
        underground: Vec<u8>,
        altitude: Vec<i32>,
        data: Vec<u8>,
    }

    impl Arrays {
        fn new(edge: usize) -> Self {
            let cells = edge * edge;
            Self {
                edge,
                buildings: vec![0; cells],
                zones: vec![0; cells],
                flags: vec![0; cells],
                underground: vec![0; cells],
                altitude: vec![0; cells],
                data: Vec::new(),
            }
        }

        fn city(&self) -> MinimapCity<'_> {
            MinimapCity {
                edge: self.edge,
                buildings: &self.buildings,
                zones: &self.zones,
                flags: &self.flags,
                underground: &self.underground,
                altitude: &self.altitude,
                data: &self.data,
                quarter: &[],
            }
        }
    }

    #[test]
    fn base_colors_follow_ground_trees_and_water() {
        let mut a = Arrays::new(8);
        a.altitude[0] = 8;
        a.flags[1] = flags::WATER;
        a.buildings[2] = RUBBLE_3;
        a.buildings[3] = TREES_1;
        a.buildings[4] = LOWER_CLASS_HOMES_1X1_1;
        let c = a.city();
        assert_eq!(c.color_index(0, 0, Mode::Structures), EMPTY_GROUND - 6);
        assert_eq!(c.color_index(0, 1, Mode::Structures), WATER_COLOR);
        assert_eq!(c.color_index(0, 2, Mode::Structures), RUBBLE_COLOR);
        assert_eq!(c.color_index(0, 3, Mode::Structures), TREE_COLOR);
        assert_eq!(c.color_index(0, 4, Mode::Structures), 0);
        assert_eq!(c.color_index(8, 0, Mode::Structures), 0);
    }

    #[test]
    fn layers_mark_networks_utilities_and_services() {
        let mut a = Arrays::new(4);
        a.buildings[0] = ROAD_STRAIGHT_1;
        a.buildings[1] = RAIL_STRAIGHT_1;
        a.buildings[2] = POWER_LINE_STRAIGHT_1;
        a.buildings[3] = POLICE_STATION;
        a.flags[4] = flags::POWERED;
        a.flags[5] = flags::POWERABLE;
        a.underground[6] = underground::PIPE_LR;
        a.flags[7] = flags::WATERED;

        // a corner bit and zone type 3
        a.zones[8] = 0x10 | 3;
        let c = a.city();
        assert_eq!(c.color_index(0, 0, Mode::Roads), HIGHLIGHT);
        assert_eq!(c.color_index(0, 1, Mode::Rail), HIGHLIGHT);
        assert_eq!(c.color_index(0, 2, Mode::Power), HIGHLIGHT);
        assert_eq!(c.color_index(0, 3, Mode::PoliceStations), HIGHLIGHT);
        assert_eq!(c.color_index(1, 0, Mode::Power), SUPPLIED);
        assert_eq!(c.color_index(1, 1, Mode::Power), CONNECTED);
        assert_eq!(c.color_index(1, 2, Mode::Water), HIGHLIGHT);
        assert_eq!(c.color_index(1, 3, Mode::Water), SUPPLIED);
        assert_eq!(c.color_index(2, 0, Mode::Zones), 92);
    }

    #[test]
    fn coarse_and_native_data_maps() {
        let mut a = Arrays::new(8);
        a.data = vec![0; 16];
        a.data[4 + 2] = 0xff;
        let c = a.city();

        // cell (1, 2) of a half-resolution grid covers tiles 2..4, 4..6
        assert_eq!(c.color_index(3, 5, Mode::Pollution), GRADIENT_BASE + 15);
        assert_eq!(c.color_index(3, 6, Mode::Pollution), c.color_index(3, 6, Mode::Structures));
        assert_eq!(c.color_index(3, 6, Mode::Growth), SHRINKING);
        let mut full = Arrays::new(8);
        full.data = vec![0x80; 64];
        assert_eq!(
            full.city().color_index(0, 0, Mode::Growth),
            full.city().color_index(0, 0, Mode::Structures)
        );
    }

    #[test]
    fn large_maps_sample_tiles() {
        let mut a = Arrays::new(2048);
        a.buildings[2 * 2048 + 4] = POLICE_STATION;
        let pixels = indices(&a.city(), Mode::PoliceStations);
        assert_eq!(pixels.len(), 1024 * 1024);

        // tile (2, 4) is image column 1, row 2
        assert_eq!(pixels[2 * 1024 + 1], HIGHLIGHT);
        let rgba = colorize(&pixels[..2], &[[1, 2, 3, 4]; 256].concat());
        assert_eq!(rgba, vec![1, 2, 3, 4, 1, 2, 3, 4]);
    }
}

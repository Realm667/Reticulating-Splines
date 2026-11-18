//! Stable, local artwork choices. Never consumes the simulation random state.
use crate::Builder;
use std::collections::HashMap;

pub const FIRST: i32 = 3_000_000;
pub const SPAN: i32 = 1500;
const ABANDONED_FIRST: i32 = FIRST + SPAN;
const ABANDONED_END: i32 = ABANDONED_FIRST + 3 * SPAN;

fn abandoned_tile(id: i32) -> bool {
    matches!(id % 500, 138 | 139 | 170..=173 | 196 | 197)
}

pub(super) fn weathered_sprite(id: i32) -> bool {
    (ABANDONED_FIRST..ABANDONED_END).contains(&id) && abandoned_tile(id)
}

#[derive(Default)]
pub struct Variants {
    pub seed: u32,
    pub original_weight: u32,
    pub abandoned_percent: u32,
    /// Original sprite ID -> (alternative sprite ID, relative weight).
    /// The asset loader sorts these by content identity, not filename/load order.
    pub choices: HashMap<i32, Vec<(i32, u32)>>,
}

impl Builder {
    pub(super) fn building_variant(&self, x: i32, y: i32, id: i32) -> i32 {
        let variants = &self.sprites.variants;
        let Some(choices) = variants.choices.get(&id) else { return id };
        let Some(image) = self.sprites.images.get(&(id as u64 * 2)) else {
            return id;
        };
        let width = self.sprites.registration.get(&(id as u64 * 2)).map_or(image.w, |r| r[0]);
        let area = (width / (32 / self.config.divisor())).max(1);
        // Each rotation uses another corner of a multi-cell footprint. Undo the
        // rotation of its center, in doubled coordinates to avoid rounding.
        let anchor = self.city.index(x, y);
        let (x, y) = (2 * x + area - 1, 2 * y - area + 1);
        let last = 2 * (self.city.edge - 1);
        let (x, y) = match self.city.rotation {
            1 => (last - y, x),
            2 => (last - x, last - y),
            3 => (y, last - x),
            _ => (x, y),
        };
        let mut hash = (x as u32).wrapping_mul(374_761_393)
            ^ (y as u32).wrapping_mul(668_265_263)
            ^ ((id % 500) as u32).wrapping_mul(2_246_822_519)
            ^ variants.seed.wrapping_mul(3_266_489_917);
        hash = (hash ^ (hash >> 13)).wrapping_mul(1_274_126_177);
        hash ^= hash >> 16;
        if abandoned_tile(id) {
            if hash % 100 >= variants.abandoned_percent {
                return id;
            }
            let sector = match self.city.zones[anchor] & 15 {
                1 | 2 => 1,
                3 | 4 => 2,
                5 | 6 => 3,
                _ => 1 + ((hash / 100) % 3) as i32,
            };
            let alias = FIRST + sector * SPAN + id;
            return if choices.iter().any(|&(sprite, _)| sprite == alias) {
                alias
            } else {
                id
            };
        }
        let total = choices.iter().fold(variants.original_weight, |sum, &(_, weight)| sum + weight);
        if total == 0 {
            return id;
        }
        let mut selected = hash % total;
        if selected < variants.original_weight {
            return id;
        }
        selected -= variants.original_weight;
        for &(sprite, weight) in choices {
            if selected < weight {
                return sprite;
            }
            selected -= weight;
        }
        id
    }
}

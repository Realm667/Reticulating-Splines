//! Stable, local artwork choices. Never consumes the simulation random state.
use crate::Builder;
use std::collections::HashMap;

pub const FIRST: i32 = 3_000_000;
pub const SPAN: i32 = 1500;

#[derive(Default)]
pub struct Variants {
    pub seed: u32,
    pub original_weight: u32,
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

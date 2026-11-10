//! Shared underground port elevations. Units are quarter native pixels.
use crate::City;
const PORTS: [u8; 15] = [5, 10, 10, 5, 10, 5, 3, 6, 12, 9, 11, 7, 14, 13, 15];
const EDGES: [[usize; 2]; 4] = [[0, 1], [1, 2], [2, 3], [3, 0]];

pub fn ports(tile: u8, pipe: bool) -> u8 {
    match (pipe, tile) {
        (false, 1..=15) => PORTS[(tile - 1) as usize],
        (true, 16..=30) => PORTS[(tile - 16) as usize],
        (false, 31) | (true, 32) => 5,
        (false, 32) | (true, 31) => 10,
        (false, 35) => 15,
        _ => 0,
    }
}

fn depth(tile: u8, pipe: bool) -> i16 {
    if pipe && matches!(tile, 31 | 32) { -24 } else { -12 }
}

pub fn profile(base: i16, tile: u8, own: [i16; 4], neighbors: [(u8, [i16; 4]); 4]) -> [i16; 13] {
    let mut result = [0; 13];
    result[12] = depth(tile, true) * 4;
    for k in 0..4 {
        result[k] = (own[k] - base * 4) * 12;
    }
    for (network, pipe) in [false, true].into_iter().enumerate() {
        for direction in 0..4 {
            let [a, b] = EDGES[direction];
            let own_height = 6 * (own[a] + own[b]) + 4 * depth(tile, pipe);
            let (other, q) = neighbors[direction];
            let opposite = (direction + 2) % 4;
            let joined = ports(tile, pipe) & (1 << direction) != 0 && ports(other, pipe) & (1 << opposite) != 0;
            let height = if joined {
                let [a, b] = EDGES[opposite];
                own_height.min(6 * (q[a] + q[b]) + 4 * depth(other, pipe))
            } else {
                own_height
            };
            result[4 + network * 4 + direction] = height - base * 48;
        }
    }
    result
}

pub fn city_profile(city: &City, i: usize) -> [i16; 13] {
    let corners = |i: usize| {
        if city.quarter.is_empty() && city.terrain[i] >= 0x30 {
            [(city.land(i) * 4) as i16; 4]
        } else {
            city.quarter_corners(i)
        }
    };
    let x = i as i32 / city.edge;
    let y = i as i32 % city.edge;
    let neighbors = std::array::from_fn(|k| {
        let (dx, dy) = [(0, -1), (1, 0), (0, 1), (-1, 0)][k];
        let (x, y) = (x + dx, y + dy);
        if x < 0 || y < 0 || x >= city.edge || y >= city.edge {
            (0, [0; 4])
        } else {
            let n = city.index(x, y);
            (city.underground[n], corners(n))
        }
    });
    profile(city.land(i) as i16, city.underground[i], corners(i), neighbors)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn every_connected_topology_pair_has_the_same_absolute_port_height() {
        let mut checks = 0;
        for a in 0..40 {
            for b in 0..40 {
                for direction in 0..4 {
                    for qa in 0..=16_i16 {
                        for qb in 0..=16_i16 {
                            let own = [qa, qa + 1, qa + 2, qa + 1];
                            let other = [qb, qb + 2, qb + 3, qb + 1];
                            let mut na = [(0, [0; 4]); 4];
                            let mut nb = na;
                            na[direction] = (b, other);
                            nb[(direction + 2) % 4] = (a, own);
                            let pa = profile(qa / 4, a, own, na);
                            let pb = profile(qb / 4, b, other, nb);
                            for (network, pipe) in [false, true].into_iter().enumerate() {
                                if ports(a, pipe) & (1 << direction) != 0 && ports(b, pipe) & (1 << ((direction + 2) % 4)) != 0 {
                                    assert_eq!(
                                        pa[4 + network * 4 + direction] + qa / 4 * 48,
                                        pb[4 + network * 4 + (direction + 2) % 4] + qb / 4 * 48
                                    );
                                    let [ea, eb] = EDGES[direction];
                                    assert!(pa[4 + network * 4 + direction] + qa / 4 * 48 <= 6 * (own[ea] + own[eb]) + 4 * depth(a, pipe));
                                    checks += 1;
                                }
                            }
                        }
                    }
                }
            }
        }
        assert!(checks > 200_000);
    }
}

//! Data overlays use the same corner heights and water clipping as the city.
use crate::data_view::{DataCity, DataMesh};
type Vertex = [f32; 3]; // local u, v and height in quarters
const CORNERS: [[f32; 2]; 4] = [[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]];

fn face(mesh: &mut DataMesh, x: usize, y: usize, edge: usize, vertices: &[Vertex], shade: f32) {
    let first = mesh.vertices.len() as i32;
    for (k, &[u, v, z]) in vertices.iter().enumerate() {
        mesh.vertices.push([
            32.0 + edge as f32 * 16.0 + (x as f32 - y as f32 + u - v) * 16.0 + 16.0,
            512.0 + (x + y) as f32 * 8.0 + (u + v) * 8.0 - z * 3.0,
        ]);
        let uv = if shade < 1.0 { CORNERS[k] } else { [u, v] };
        mesh.uvs.push([y as f32 * 2.0 + uv[0], x as f32 * 2.0 + uv[1]]);
        mesh.colors.push([1.0, 1.0, shade, 1.0]);
    }
    for i in 1..vertices.len() - 1 {
        mesh.indices.extend([first, first + i as i32, first + i as i32 + 1]);
    }
}

fn clip(vertices: &[Vertex], water: f32, above: bool) -> Vec<Vertex> {
    let mut out = Vec::new();
    let mut a = *vertices.last().unwrap();
    for &b in vertices {
        let inside = |p: Vertex| if above { p[2] >= water } else { p[2] <= water };
        if inside(a) != inside(b) {
            let t = (water - a[2]) / (b[2] - a[2]);
            out.push([a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, water]);
        }
        if inside(b) {
            out.push(b);
        }
        a = b;
    }
    out
}

fn height(city: &DataCity, i: usize, a: usize, b: usize, t: f32, seabed: bool) -> f32 {
    let q = city.quarter[i];
    let land = f32::from(q[a]) + (f32::from(q[b]) - f32::from(q[a])) * t;
    if !seabed && city.flags[i] & 4 != 0 {
        land.max(((city.altitude[i] >> 5) & 31) as f32 * 4.0)
    } else {
        land
    }
}

pub fn build(city: &DataCity, seabed: bool) -> DataMesh {
    window(
        city,
        seabed,
        crate::debug_view::geometry::TileWindow {
            x0: 0,
            y0: 0,
            x1: city.edge,
            y1: city.edge,
        },
    )
}

pub(crate) fn window(city: &DataCity, seabed: bool, window: crate::debug_view::geometry::TileWindow) -> DataMesh {
    let mut mesh = DataMesh {
        quarter_height: true,
        ..DataMesh::default()
    };
    let edge = city.edge;
    if window.is_empty() {
        return mesh;
    }
    let width = window.x1 - window.x0;
    let rows = window.y1 - window.y0;
    for diagonal in 0..width + rows - 1 {
        for row in diagonal.saturating_sub(width - 1)..=(rows - 1).min(diagonal) {
            let x = window.x0 + diagonal - row;
            let y = window.y0 + row;
            let i = x * edge + y;
            if !city.visible(i, seabed) {
                continue;
            }
            let top: [Vertex; 4] = std::array::from_fn(|k| [CORNERS[k][0], CORNERS[k][1], f32::from(city.quarter[i][k])]);
            // Front walls split at coast intersections and at crossing independent edges.
            for (a, b, neighbor, na, nb, shade) in [
                (1, 2, (x + 1 < edge).then_some(i + edge), 0, 3, 0.78),
                (2, 3, (y + 1 < edge).then_some(i + 1), 1, 0, 0.65),
            ] {
                let neighbor = neighbor.filter(|n| city.visible(*n, seabed));
                let own = |t| height(city, i, a, b, t, seabed);
                let other = |t| neighbor.map_or(0.0, |n| height(city, n, na, nb, t, seabed));
                let mut cuts = vec![0.0, 1.0];
                for (n, aa, bb) in std::iter::once((i, a, b)).chain(neighbor.map(|n| (n, na, nb))) {
                    if !seabed && city.flags[n] & 4 != 0 {
                        let q = city.quarter[n];
                        let w = ((city.altitude[n] >> 5) & 31) as f32 * 4.0;
                        let dz = f32::from(q[bb] - q[aa]);
                        if dz != 0.0 {
                            let t = (w - f32::from(q[aa])) / dz;
                            if t > 0.0 && t < 1.0 {
                                cuts.push(t);
                            }
                        }
                    }
                }
                cuts.sort_by(f32::total_cmp);
                let mut crossings = Vec::new();
                for interval in cuts.windows(2) {
                    let d0 = own(interval[0]) - other(interval[0]);
                    let d1 = own(interval[1]) - other(interval[1]);
                    if d0 * d1 < 0.0 {
                        crossings.push(interval[0] + (interval[1] - interval[0]) * d0 / (d0 - d1));
                    }
                }
                cuts.extend(crossings);
                cuts.sort_by(f32::total_cmp);
                cuts.dedup();
                for interval in cuts.windows(2) {
                    let [t0, t1] = [interval[0], interval[1]];
                    if own((t0 + t1) * 0.5) <= other((t0 + t1) * 0.5) {
                        continue;
                    }
                    let at = |t, z| [top[a][0] + (top[b][0] - top[a][0]) * t, top[a][1] + (top[b][1] - top[a][1]) * t, z];
                    face(
                        &mut mesh,
                        x,
                        y,
                        edge,
                        &[at(t0, own(t0)), at(t1, own(t1)), at(t1, other(t1)), at(t0, other(t0))],
                        shade,
                    );
                }
            }
            for indices in [[0, 1, 2], [0, 2, 3]] {
                let triangle = indices.map(|k| top[k]);
                if !seabed && city.flags[i] & 4 != 0 {
                    let water = ((city.altitude[i] >> 5) & 31) as f32 * 4.0;
                    if triangle.iter().all(|p| p[2] == water) {
                        face(&mut mesh, x, y, edge, &triangle, 1.0);
                        continue;
                    }
                    let land = clip(&triangle, water, true);
                    if land.len() >= 3 {
                        face(&mut mesh, x, y, edge, &land, 1.0);
                    }
                    let mut wet = clip(&triangle, water, false);
                    for vertex in &mut wet {
                        vertex[2] = water;
                    }
                    if wet.len() >= 3 {
                        face(&mut mesh, x, y, edge, &wet, 1.0);
                    }
                } else {
                    face(&mut mesh, x, y, edge, &triangle, 1.0);
                }
            }
        }
    }
    mesh
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_relative_corner_shape_and_water_split_preserves_the_complete_tile() {
        let mut cases = 0;
        for encoded in 0..9_usize.pow(4) {
            let q = std::array::from_fn(|k| ((encoded / 9_usize.pow(k as u32)) % 9) as i16);
            for (wet, water) in [(false, 0), (true, 0), (true, 1), (true, 2), (true, 31)] {
                for seabed in [false, true] {
                    let city = DataCity {
                        edge: 1,
                        visible: 32,
                        altitude: &[water << 5],
                        terrain: &[0],
                        flags: &[if wet { 4 } else { 0 }],
                        quarter: &[q],
                    };
                    let mesh = build(&city, seabed);
                    assert!(mesh.quarter_height);
                    assert!(mesh.vertices.iter().flatten().all(|v| v.is_finite()));
                    assert_eq!(mesh.vertices.len(), mesh.uvs.len());
                    let mut area = 0.0;
                    for tri in mesh.indices.chunks_exact(3) {
                        let [a, b, c] = [tri[0] as usize, tri[1] as usize, tri[2] as usize];
                        assert!(c < mesh.vertices.len());
                        if mesh.colors[a][2] == 1.0 {
                            let [a, b, c] = [mesh.uvs[a], mesh.uvs[b], mesh.uvs[c]];
                            area += ((b[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (b[1] - a[1])).abs() * 0.5;
                        }
                    }
                    assert!(
                        (area - 1.0).abs() < 0.00001,
                        "missing/overlapping top: {q:?}, water {water}, wet {wet}, seabed {seabed}"
                    );
                    cases += 1;
                }
            }
        }
        assert_eq!(cases, 65_610);
    }

    #[test]
    fn all_absolute_quarter_levels_move_every_view_and_retain_fractional_values() {
        for level in 0..=128_i16 {
            let city = DataCity {
                edge: 1,
                visible: 32,
                altitude: &[i32::from(level / 4).min(31)],
                terrain: &[0],
                flags: &[0],
                quarter: &[[level; 4]],
            };
            assert!(city.validate().is_ok());
            let mesh = build(&city, false);
            assert!(mesh.vertices.contains(&[64.0, 512.0 - f32::from(level) * 3.0]));
            assert_eq!(
                crate::data_view::fractional_heights(city.altitude, city.flags, city.quarter),
                vec![f32::from(level) / 4.0]
            );
            for cut in 0..=32 {
                let cut_city = DataCity { visible: cut, ..city };
                assert_eq!(
                    !build(&cut_city, false).vertices.is_empty(),
                    cut == 32 || i32::from(level) < cut * 4
                );
            }
        }
        assert_eq!(
            crate::data_view::fractional_heights(&[3 << 5], &[4], &[[8, 9, 10, 11]]),
            vec![64.625]
        );
    }
}

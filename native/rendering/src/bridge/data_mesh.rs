//! Data map overlay geometry.

use godot::prelude::*;
use sc2k_render::data_view;

/// Data map overlay geometry. See `data_view.rs`.
#[derive(GodotClass)]
#[class(base=Object, no_init)]
pub struct NativeCityDataMesh {}
#[godot_api]
impl NativeCityDataMesh {
    #[func]
    fn underground_profile(
        base: i64,
        tile: i64,
        own: PackedInt32Array,
        neighbors: PackedInt32Array,
        tiles: PackedInt32Array,
    ) -> PackedInt32Array {
        let Ok(own) = quarter_corners(own.as_slice(), 1) else {
            return PackedInt32Array::new();
        };
        let Ok(neighbors) = quarter_corners(neighbors.as_slice(), 4) else {
            return PackedInt32Array::new();
        };
        if own.is_empty()
            || neighbors.is_empty()
            || tiles.len() != 4
            || !(0..32).contains(&base)
            || !(0..=255).contains(&tile)
            || tiles.as_slice().iter().any(|t| !(0..=255).contains(t))
        {
            return PackedInt32Array::new();
        }
        let profile = sc2k_render::underground_models::profile(
            base as i16,
            tile as u8,
            own[0],
            std::array::from_fn(|k| (tiles[k] as u8, neighbors[k])),
        );
        profile.into_iter().map(i32::from).collect()
    }

    /// `{vertices, colors, uvs, indices}`, or `{error}`. `altitude` holds the ALTM words.
    #[func]
    fn build(
        edge: i64,
        visible: i64,
        height_view: bool,
        altitude: PackedInt32Array,
        terrain: PackedByteArray,
        flags: PackedByteArray,
    ) -> VarDictionary {
        Self::build_quarter(edge, visible, height_view, altitude, terrain, flags, PackedInt32Array::new())
    }

    #[func]
    fn build_quarter(
        edge: i64,
        visible: i64,
        height_view: bool,
        altitude: PackedInt32Array,
        terrain: PackedByteArray,
        flags: PackedByteArray,
        corners: PackedInt32Array,
    ) -> VarDictionary {
        let mut result = VarDictionary::new();
        let quarter = match quarter_corners(corners.as_slice(), edge.max(0) as usize * edge.max(0) as usize) {
            Ok(q) => q,
            Err(error) => {
                result.set("error", &GString::from(&error));
                return result;
            }
        };
        let city = data_view::DataCity {
            edge: edge.max(0) as usize,
            visible: visible as i32,
            altitude: altitude.as_slice(),
            terrain: terrain.as_slice(),
            flags: flags.as_slice(),
            quarter: &quarter,
        };

        if let Err(error) = city.validate() {
            result.set("error", &GString::from(&error));

            return result;
        }

        let mesh = data_view::build(&city, height_view);
        let vertices: PackedVector2Array = mesh.vertices.iter().map(|v| Vector2::new(v[0], v[1])).collect();
        let colors: PackedColorArray = mesh.colors.iter().map(|c| Color::from_rgba(c[0], c[1], c[2], c[3])).collect();
        let uvs: PackedVector2Array = mesh.uvs.iter().map(|v| Vector2::new(v[0], v[1])).collect();
        result.set("vertices", &vertices);
        result.set("colors", &colors);
        result.set("uvs", &uvs);
        result.set("indices", &PackedInt32Array::from(mesh.indices.as_slice()));
        result
    }
}

/// Tile values of the data maps that have no data chunk. See `data_view.rs`.
#[godot_api(secondary)]
impl NativeCityDataMesh {
    #[func]
    fn fractional_heights(altitude: PackedInt32Array, flags: PackedByteArray, corners: PackedInt32Array) -> PackedFloat32Array {
        if flags.len() != altitude.len() {
            return PackedFloat32Array::new();
        }
        let Ok(quarter) = quarter_corners(corners.as_slice(), altitude.len()) else {
            return PackedFloat32Array::new();
        };
        PackedFloat32Array::from(data_view::fractional_heights(altitude.as_slice(), flags.as_slice(), &quarter).as_slice())
    }
    /// The land level of each dry tile, and the underwater base plus the water
    /// depth of each underwater tile. `altitude` holds the ALTM words.
    #[func]
    fn height_values(altitude: PackedInt32Array, flags: PackedByteArray) -> PackedByteArray {
        PackedByteArray::from(data_view::height_values(altitude.as_slice(), flags.as_slice()).as_slice())
    }

    #[constant]
    const UNDERWATER_BASE: i32 = data_view::UNDERWATER_BASE as i32;

    /// 2 where the `supplied` flag is set, 1 where only `connected` is set.
    #[func]
    fn utility_values(flags: PackedByteArray, supplied: i64, connected: i64) -> PackedByteArray {
        PackedByteArray::from(data_view::utility_values(flags.as_slice(), supplied as u8, connected as u8).as_slice())
    }
}

pub(super) fn quarter_corners(flat: &[i32], cells: usize) -> Result<Vec<[i16; 4]>, String> {
    if flat.is_empty() {
        return Ok(Vec::new());
    }
    if flat.len() != cells * 4 || flat.iter().any(|q| !(0..=128).contains(q)) {
        return Err("invalid quarter-height corner array".into());
    }
    Ok(flat.chunks_exact(4).map(|q| std::array::from_fn(|k| q[k] as i16)).collect())
}

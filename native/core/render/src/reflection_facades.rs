//! Facade-only reflections for verified original cuboid artwork. Geometry is
//! metadata, not redistributed artwork. Different SCURK/HD silhouettes retain
//! the generic path instead of inheriting the wrong original-building model.
use crate::{Draw, sprites::Sprite};

#[derive(Clone, Copy)]
pub(super) struct Facade {
    top: [f32; 6],
    height: f32,
    canvas_height: f32,
    divisor: f32,
}

impl Facade {
    pub fn for_sprite(draw: &Draw, sprite: &Sprite) -> Option<Self> {
        let (fingerprints, profile) = match (draw.sprite, sprite.w, sprite.h) {
            (147, 16, 20) => Some((
                [16090280062341287090, 15846941003769632462],
                Self {
                    top: [11.0, 11.0, 32.0, 21.5, 57.0, 9.0],
                    height: 48.0,
                    canvas_height: 77.0,
                    divisor: 4.0,
                },
            )),
            (647, 32, 39) => Some((
                [17332501136551607272, 11279148554892604292],
                Self {
                    top: [11.0, 11.0, 32.0, 21.5, 57.0, 9.0],
                    height: 48.0,
                    canvas_height: 77.0,
                    divisor: 2.0,
                },
            )),
            (1147, 64, 77) => Some((
                [17937034326972927371, 3499918209789505291],
                Self {
                    top: [11.0, 11.0, 32.0, 21.5, 57.0, 9.0],
                    height: 48.0,
                    canvas_height: 77.0,
                    divisor: 1.0,
                },
            )),
            (183, 24, 30) => Some((
                [6151941937633920274, 4970251782970350650],
                Self {
                    top: [17.0, 16.0, 47.0, 31.0, 78.0, 15.5],
                    height: 73.0,
                    canvas_height: 117.0,
                    divisor: 4.0,
                },
            )),
            (683, 48, 59) => Some((
                [15719499332938941704, 7205519538943338052],
                Self {
                    top: [17.0, 16.0, 47.0, 31.0, 78.0, 15.5],
                    height: 73.0,
                    canvas_height: 117.0,
                    divisor: 2.0,
                },
            )),
            (1183, 96, 117) => Some((
                [7102616014229886469, 2781854916734009529],
                Self {
                    top: [17.0, 16.0, 47.0, 31.0, 78.0, 15.5],
                    height: 73.0,
                    canvas_height: 117.0,
                    divisor: 1.0,
                },
            )),
            _ => None,
        }?;
        let fingerprint = sprite.rgba.chunks_exact(4).fold(0xcbf29ce484222325_u64, |hash, p| {
            [p[0], p[3]]
                .into_iter()
                .fold(hash, |h, b| (h ^ u64::from(b)).wrapping_mul(0x100000001b3))
        });
        (fingerprint == fingerprints[usize::from(draw.flip)]).then_some(profile)
    }

    // Source-row bounds and twice the reflecting plane, in global pixel units.
    pub fn column(self, draw: &Draw, column: i32) -> Option<(f32, f32, i32)> {
        let column = if draw.flip { draw.rect.w - 1 - column } else { column };
        let x = (column as f32 + 0.5) * self.divisor;
        let [lx, ly, cx, cy, rx, ry] = self.top;
        if x < lx || x >= rx {
            return None;
        }
        let (ax, ay, bx, by) = if x < cx { (lx, ly, cx, cy) } else { (cx, cy, rx, ry) };
        let top = ay + (by - ay) * (x - ax) / (bx - ax);
        let top = (top - self.canvas_height) / self.divisor + draw.rect.h as f32;
        let foot = top + self.height / self.divisor;
        Some((top, foot, (2.0 * (draw.rect.y as f32 + foot)).round() as i32))
    }
}

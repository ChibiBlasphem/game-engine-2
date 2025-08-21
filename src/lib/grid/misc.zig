const std = @import("std");
const coord = @import("../coord.zig");

const GridPoint = extern struct {
    position: coord.Vec3,
    color: [3]f32,

    pub fn init(position: coord.Vec3, color: [3]f32) GridPoint {
        return GridPoint{ .position = position, .color = color };
    }
};

pub fn buildGrid(alloc: std.mem.Allocator, slices: u32, spacing: f32) ![]GridPoint {
    // Nombre de lignes : 2 directions * (2*slices + 1)  =  4*slices + 2
    const line_count: usize = @intCast(4 * slices + 2);
    const vert_count: usize = line_count * 2; // 2 sommets par ligne

    var verts = try alloc.alloc(GridPoint, vert_count);
    var idx: usize = 0;

    const half = @as(f32, @floatFromInt(slices)) * spacing;

    // i va de -slices à +slices (inclus)
    var i: i32 = -@as(i32, @intCast(slices));
    const i_end: i32 = @as(i32, @intCast(slices));

    while (i <= i_end) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) * spacing;

        // Lignes parallèles à X (const z = t)
        const col_x = if (i == 0) [_]f32{ 1.0, 0.0, 0.0 } else [_]f32{ 0.6, 0.6, 0.6 };
        verts[idx] = GridPoint.init(coord.Vec3.init(-half, 0.0, t), col_x);
        idx += 1;
        verts[idx] = GridPoint.init(coord.Vec3.init(half, 0.0, t), col_x);
        idx += 1;

        // Lignes parallèles à Z (const x = t)
        const col_z = if (i == 0) [_]f32{ 0.0, 0.0, 1.0 } else [_]f32{ 0.6, 0.6, 0.6 };
        verts[idx] = GridPoint.init(coord.Vec3.init(t, 0.0, -half), col_z);
        idx += 1;
        verts[idx] = GridPoint.init(coord.Vec3.init(t, 0.0, half), col_z);
        idx += 1;
    }

    std.debug.assert(idx == verts.len);
    return verts;
}

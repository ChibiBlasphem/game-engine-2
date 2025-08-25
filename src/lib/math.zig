const std = @import("std");

// region Math.Primitives
inline fn prim(comptime N: usize, comptime T: type, comptime name: []const u8) type {
    return extern struct {
        const P = @This();
        const VecType = @Vector(N, T);
        const IsFloat = @typeInfo(T) == .float;
        const FT = if (IsFloat) T else f32;

        pub const ZERO: P = .splat(0);
        pub const ONE: P = .splat(1);

        data: VecType align(@sizeOf(T)),

        pub inline fn init(v: @Vector(N, T)) P {
            return .{ .data = v };
        }

        pub inline fn splat(v: T) P {
            return .{ .data = @splat(v) };
        }

        pub inline fn len(v: P) f32 {
            const vf: @Vector(N, FT) = if (IsFloat) v.data else @floatFromInt(v.data);
            return @sqrt(@reduce(.Add, vf * vf));
        }

        pub inline fn add(a: P, b: P) P {
            return .init(a.data + b.data);
        }

        pub inline fn sub(a: P, b: P) P {
            return .init(a.data - b.data);
        }

        pub inline fn scale(a: P, s: T) P {
            return .{ .data = a.data * @as(VecType, @splat(s)) };
        }

        pub inline fn normalize(a: P) P {
            const l = @sqrt(a.dot(a));
            return a.scale(1.0 / l);
        }

        pub inline fn dot(a: P, b: P) T {
            return @reduce(.Add, a.data * b.data);
        }

        pub usingnamespace if (N == 3) struct {
            pub inline fn cross(a: P, b: P) P {
                const yzx: @Vector(3, i32) = .{ 1, 2, 0 };
                const zxy: @Vector(3, i32) = .{ 2, 0, 1 };

                const a_yzx = @shuffle(T, a.data, a.data, yzx);
                const a_zxy = @shuffle(T, a.data, a.data, zxy);
                const b_zxy = @shuffle(T, b.data, b.data, zxy);
                const b_yzx = @shuffle(T, b.data, b.data, yzx);

                return .init(a_yzx * b_zxy - a_zxy * b_yzx);
            }
        } else struct {};

        // region prim.format
        pub inline fn format(self: P, comptime fmt: []const u8, opts: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = opts;
            try writer.print("{s}{{", .{name});
            inline for (0..N) |i| {
                try writer.print("{d}", .{self.data[i]});
                if (i + 1 < N) try writer.writeAll(", ");
            }
            try writer.writeByte('}');
        }
        // endregion
    };
}
// endregion

// region Math.Structs
pub const f32x2 = prim(2, f32, "f32x2");
pub const f32x3 = prim(3, f32, "f32x3");
pub const i32x2 = prim(2, i32, "i32x2");
pub const i32x3 = prim(3, i32, "i32x3");

// Column-major matrix
pub const mat4x4 = extern struct {
    const P = @This();
    const Vec = @Vector(4, f32);
    const Mat = @Vector(16, f32);
    const identity: Mat = .{
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    };

    pub const IDENTITY: P = .init(identity);

    data: Mat align(16),

    // region mat4x4.Lifecycle
    pub inline fn init(v: [16]f32) P {
        return .{ .data = v };
    }

    pub inline fn translation(t: anytype) P {
        const _t3d = switch (@TypeOf(t)) {
            f32x2 => f32x3.init(.{ t.data[0], t.data[1], 0 }),
            f32x3 => t,
            else => @compileError("Only f32x2 or f32x3 is allowed for translate"),
        };

        var mat = identity;
        mat[12] = _t3d.data[0];
        mat[13] = _t3d.data[1];
        mat[14] = _t3d.data[2];
        return .{ .data = mat };
    }

    pub inline fn scaling(s: anytype) P {
        const _s3d = switch (@TypeOf(s)) {
            f32x2 => f32x3.init(.{ s.data[0], s.data[1], 1 }),
            f32x3 => s,
            else => @compileError("Only f32x2 or f32x3 is allowed for scaling"),
        };

        var mat = identity;
        mat[0] = _s3d.data[0];
        mat[5] = _s3d.data[1];
        mat[10] = _s3d.data[2];
        return .{ .data = mat };
    }

    pub inline fn rotationX(a: f32) P {
        const c = @cos(a);
        const s = @sin(a);

        return .{
            .data = .{
                1, 0,  0, 0,
                0, c,  s, 0,
                0, -s, c, 0,
                0, 0,  0, 1,
            },
        };
    }

    pub inline fn rotationY(a: f32) P {
        const c = @cos(a);
        const s = @sin(a);

        return .{
            .data = .{
                c, 0, -s, 0,
                0, 1, 0,  0,
                s, 0, c,  0,
                0, 0, 0,  1,
            },
        };
    }

    pub inline fn rotationZ(a: f32) P {
        const c = @cos(a);
        const s = @cos(a);

        return .{
            .data = .{
                c,  s, 0, 0,
                -s, c, 0, 0,
                0,  0, 1, 0,
                0,  0, 0, 1,
            },
        };
    }
    // endregion

    pub inline fn mul(a: P, b: P) P {
        const A: [4]Vec = @bitCast(a.data);
        const B: [4]Vec = @bitCast(b.data);

        var R: [4]Vec = undefined;
        inline for (0..4) |j| {
            const bj = B[j];
            var col = A[0] * @as(Vec, @splat(bj[0]));
            col = @mulAdd(Vec, A[1], @as(Vec, @splat(bj[1])), col);
            col = @mulAdd(Vec, A[2], @as(Vec, @splat(bj[2])), col);
            col = @mulAdd(Vec, A[3], @as(Vec, @splat(bj[3])), col);
            R[j] = col;
        }

        return .{ .data = @bitCast(R) };
    }

    pub inline fn perspective(fovy: f32, aspect: f32, near: f32, far: f32) P {
        const f = 1.0 / @tan(deg2rad(fovy) * 0.5);
        const nf = 1.0 / (near - far);

        return .init(.{
            f / aspect, 0, 0,                     0,
            0,          f, 0,                     0,
            0,          0, (far + near) * nf,     -1,
            0,          0, (2 * far * near) * nf, 0,
        });
    }

    pub inline fn lookAt(p: f32x3, t: f32x3, world_up: f32x3) P {
        const fwd = t.sub(p).normalize();
        const right = fwd.cross(world_up).normalize();
        const up = right.cross(fwd);

        return .{
            .data = .{
                right.data[0], up.data[0], -fwd.data[0], 0,
                right.data[1], up.data[1], -fwd.data[1], 0,
                right.data[2], up.data[2], -fwd.data[2], 0,
                -right.dot(p), -up.dot(p), fwd.dot(p),   1,
            },
        };
    }
};
// endregion

// region Math.Tests
test "f32xN.len" {
    const v = f32x2.init(.{ 3, 4 });
    try std.testing.expectApproxEqRel(5, v.len(), 0.0001);
}

test "f32xN.dot" {
    const v0 = f32x3.init(.{ -1, 2, 3 });
    const v1 = f32x3.init(.{ 4, 5, 6 });
    const act = v0.dot(v1);

    try std.testing.expectApproxEqRel(24, act, 0.0001);
}

test "f32xN.normalize" {
    const v = f32x3.init(.{ 2, 1, 0 });
    const n = f32x3.init(.{ 0.8944272, 0.4472136, 0 });
    try std.testing.expectEqual(n, v.normalize());
}

test "f32x3.cross" {
    {
        const v0 = f32x3.init(.{ 1, 0, 0 });
        const v1 = f32x3.init(.{ 0, 1, 0 });
        const vexp = f32x3.init(.{ 0, 0, 1 });
        const vact = v0.cross(v1);

        inline for (0..3) |i| {
            try std.testing.expectApproxEqRel(vexp.data[i], vact.data[i], 0.0001);
        }
    }
}

test "mat4x4.mul" {
    const a_mat: mat4x4 = .init(.{ 5, 0, 3, 1, 2, 6, 8, 8, 6, 2, 1, 5, 1, 0, 4, 6 });
    const b_mat: mat4x4 = .init(.{ 7, 1, 9, 5, 5, 8, 4, 3, 8, 2, 3, 7, 0, 6, 8, 9 });
    const res_mat: mat4x4 = .init(.{ 96, 24, 58, 90, 68, 56, 95, 107, 69, 18, 71, 81, 69, 52, 92, 142 });

    try std.testing.expectEqual(res_mat, a_mat.mul(b_mat));
}
// endregion

// pub fn matrixOrtho2D(aspect: f32, zoom: f32) [16]f32 {
//     const l: f32 = -zoom * aspect;
//     const r: f32 = zoom * aspect;
//     const b: f32 = -zoom;
//     const t: f32 = zoom;
//     const n: f32 = -1.0;
//     const f: f32 = 1.0;

//     return .{
//         2.0 / (r - l),      0,                  0,             0,
//         0,                  2.0 / (t - b),      0,             0,
//         0,                  0,                  1.0 / (f - n), 0,
//         -(r + l) / (r - l), -(t + b) / (t - b), -n / (f - n),  1,
//     };
// }

// pub fn matrixView2D(cam_x: f32, cam_y: f32, cam_rot: f32) [16]f32 {
//     const Tinv = matrixTranslate2D(-cam_x, -cam_y);
//     const Rinv = matrixRotateZ(-cam_rot);
//     return matrixMult(Rinv, Tinv);
// }

pub fn deg2rad(angle: f32) f32 {
    return angle * (std.math.pi / 180.0);
}

pub fn clampf(value: f32, min: f32, max: f32) f32 {
    return if (value < min) min else if (value > max) max else value;
}

pub fn clamp(value: i32, min: i32, max: i32) i32 {
    return if (value < min) min else if (value > max) max else value;
}

pub fn mat4Inverse(mat: mat4x4) mat4x4 {
    const m = mat.data;
    var inv: [16]f32 = undefined;

    inv[0] = m[5] * m[10] * m[15] - m[5] * m[11] * m[14] - m[9] * m[6] * m[15] + m[9] * m[7] * m[14] + m[13] * m[6] * m[11] - m[13] * m[7] * m[10];
    inv[4] = -m[4] * m[10] * m[15] + m[4] * m[11] * m[14] + m[8] * m[6] * m[15] - m[8] * m[7] * m[14] - m[12] * m[6] * m[11] + m[12] * m[7] * m[10];
    inv[8] = m[4] * m[9] * m[15] - m[4] * m[11] * m[13] - m[8] * m[5] * m[15] + m[8] * m[7] * m[13] + m[12] * m[5] * m[11] - m[12] * m[7] * m[9];
    inv[12] = -m[4] * m[9] * m[14] + m[4] * m[10] * m[13] + m[8] * m[5] * m[14] - m[8] * m[6] * m[13] - m[12] * m[5] * m[10] + m[12] * m[6] * m[9];

    inv[1] = -m[1] * m[10] * m[15] + m[1] * m[11] * m[14] + m[9] * m[2] * m[15] - m[9] * m[3] * m[14] - m[13] * m[2] * m[11] + m[13] * m[3] * m[10];
    inv[5] = m[0] * m[10] * m[15] - m[0] * m[11] * m[14] - m[8] * m[2] * m[15] + m[8] * m[3] * m[14] + m[12] * m[2] * m[11] - m[12] * m[3] * m[10];
    inv[9] = -m[0] * m[9] * m[15] + m[0] * m[11] * m[13] + m[8] * m[1] * m[15] - m[8] * m[3] * m[13] - m[12] * m[1] * m[11] + m[12] * m[3] * m[9];
    inv[13] = m[0] * m[9] * m[14] - m[0] * m[10] * m[13] - m[8] * m[1] * m[14] + m[8] * m[2] * m[13] + m[12] * m[1] * m[10] - m[12] * m[2] * m[9];

    inv[2] = m[1] * m[6] * m[15] - m[1] * m[7] * m[14] - m[5] * m[2] * m[15] + m[5] * m[3] * m[14] + m[13] * m[2] * m[7] - m[13] * m[3] * m[6];
    inv[6] = -m[0] * m[6] * m[15] + m[0] * m[7] * m[14] + m[4] * m[2] * m[15] - m[4] * m[3] * m[14] - m[12] * m[2] * m[7] + m[12] * m[3] * m[6];
    inv[10] = m[0] * m[5] * m[15] - m[0] * m[7] * m[13] - m[4] * m[1] * m[15] + m[4] * m[3] * m[13] + m[12] * m[1] * m[7] - m[12] * m[3] * m[5];
    inv[14] = -m[0] * m[5] * m[14] + m[0] * m[6] * m[13] + m[4] * m[1] * m[14] - m[4] * m[2] * m[13] - m[12] * m[1] * m[6] + m[12] * m[2] * m[5];

    inv[3] = -m[1] * m[6] * m[11] + m[1] * m[7] * m[10] + m[5] * m[2] * m[11] - m[5] * m[3] * m[10] - m[9] * m[2] * m[7] + m[9] * m[3] * m[6];
    inv[7] = m[0] * m[6] * m[11] - m[0] * m[7] * m[10] - m[4] * m[2] * m[11] + m[4] * m[3] * m[10] + m[8] * m[2] * m[7] - m[8] * m[3] * m[6];
    inv[11] = -m[0] * m[5] * m[11] + m[0] * m[7] * m[9] + m[4] * m[1] * m[11] - m[4] * m[3] * m[9] - m[8] * m[1] * m[7] + m[8] * m[3] * m[5];
    inv[15] = m[0] * m[5] * m[10] - m[0] * m[6] * m[9] - m[4] * m[1] * m[10] + m[4] * m[2] * m[9] + m[8] * m[1] * m[6] - m[8] * m[2] * m[5];

    const det = m[0] * inv[0] + m[1] * inv[4] + m[2] * inv[8] + m[3] * inv[12];
    // tu peux remplacer par un if + retour valeur neutre si tu préfères
    std.debug.assert(@abs(det) > 1e-8);

    const inv_det = 1.0 / det;
    var out: [16]f32 = undefined;
    var i: usize = 0;
    while (i < 16) : (i += 1) out[i] = inv[i] * inv_det;

    return .{ .data = out };
}

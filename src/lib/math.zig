const std = @import("std");

pub fn matrixIdentity() [16]f32 {
    return .{
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    };
}

pub fn matrixMult(a: [16]f32, b: [16]f32) [16]f32 {
    var r: [16]f32 = undefined;
    // colonne-major: r = a * b
    r[0] = a[0] * b[0] + a[4] * b[1] + a[8] * b[2] + a[12] * b[3];
    r[4] = a[0] * b[4] + a[4] * b[5] + a[8] * b[6] + a[12] * b[7];
    r[8] = a[0] * b[8] + a[4] * b[9] + a[8] * b[10] + a[12] * b[11];
    r[12] = a[0] * b[12] + a[4] * b[13] + a[8] * b[14] + a[12] * b[15];

    r[1] = a[1] * b[0] + a[5] * b[1] + a[9] * b[2] + a[13] * b[3];
    r[5] = a[1] * b[4] + a[5] * b[5] + a[9] * b[6] + a[13] * b[7];
    r[9] = a[1] * b[8] + a[5] * b[9] + a[9] * b[10] + a[13] * b[11];
    r[13] = a[1] * b[12] + a[5] * b[13] + a[9] * b[14] + a[13] * b[15];

    r[2] = a[2] * b[0] + a[6] * b[1] + a[10] * b[2] + a[14] * b[3];
    r[6] = a[2] * b[4] + a[6] * b[5] + a[10] * b[6] + a[14] * b[7];
    r[10] = a[2] * b[8] + a[6] * b[9] + a[10] * b[10] + a[14] * b[11];
    r[14] = a[2] * b[12] + a[6] * b[13] + a[10] * b[14] + a[14] * b[15];

    r[3] = a[3] * b[0] + a[7] * b[1] + a[11] * b[2] + a[15] * b[3];
    r[7] = a[3] * b[4] + a[7] * b[5] + a[11] * b[6] + a[15] * b[7];
    r[11] = a[3] * b[8] + a[7] * b[9] + a[11] * b[10] + a[15] * b[11];
    r[15] = a[3] * b[12] + a[7] * b[13] + a[11] * b[14] + a[15] * b[15];
    return r;
}

pub fn matrixTranslate2D(x: f32, y: f32) [16]f32 {
    var m = matrixIdentity();
    m[12] = x;
    m[13] = y;
    return m;
}

pub fn matrixScale2D(sx: f32, sy: f32) [16]f32 {
    return .{
        sx, 0,  0, 0,
        0,  sy, 0, 0,
        0,  0,  1, 0,
        0,  0,  0, 1,
    };
}

pub fn matrixTranslate3D(x: f32, y: f32, z: f32) [16]f32 {
    var m = matrixIdentity();
    m[12] = x;
    m[13] = y;
    m[14] = z;
    return m;
}

pub fn matrixScale3D(sx: f32, sy: f32, sz: f32) [16]f32 {
    return .{
        sx, 0,  0,  0,
        0,  sy, 0,  0,
        0,  0,  sz, 0,
        0,  0,  0,  1,
    };
}

pub fn matrixRotateX(a: f32) [16]f32 {
    const c = @cos(a);
    const s = @sin(a);
    return .{
        1, 0,  0, 0,
        0, c,  s, 0,
        0, -s, c, 0,
        0, 0,  0, 1,
    };
}

pub fn matrixRotateY(a: f32) [16]f32 {
    const c = @cos(a);
    const s = @sin(a);
    return .{
        c, 0, -s, 0,
        0, 1, 0,  0,
        s, 0, c,  0,
        0, 0, 0,  1,
    };
}

pub fn matrixRotateZ(a: f32) [16]f32 {
    const c = @cos(a);
    const s = @sin(a);
    return .{
        c,  s, 0, 0,
        -s, c, 0, 0,
        0,  0, 1, 0,
        0,  0, 0, 1,
    };
}

pub fn matrixOrtho2D(aspect: f32, zoom: f32) [16]f32 {
    const l: f32 = -zoom * aspect;
    const r: f32 = zoom * aspect;
    const b: f32 = -zoom;
    const t: f32 = zoom;
    const n: f32 = -1.0;
    const f: f32 = 1.0;

    return .{
        2.0 / (r - l),      0,                  0,             0,
        0,                  2.0 / (t - b),      0,             0,
        0,                  0,                  1.0 / (f - n), 0,
        -(r + l) / (r - l), -(t + b) / (t - b), -n / (f - n),  1,
    };
}

pub fn matrixView2D(cam_x: f32, cam_y: f32, cam_rot: f32) [16]f32 {
    const Tinv = matrixTranslate2D(-cam_x, -cam_y);
    const Rinv = matrixRotateZ(-cam_rot);
    return matrixMult(Rinv, Tinv);
}

pub fn matrixPerspective(fov_y_deg: f32, aspect: f32, z_near: f32, z_far: f32) [16]f32 {
    const f = 1.0 / @tan((fov_y_deg * std.math.pi / 180.0) * 0.5);
    const nf = 1.0 / (z_near - z_far);
    return .{
        f / aspect, 0, 0,                         0,
        0,          f, 0,                         0,
        0,          0, (z_far + z_near) * nf,     -1,
        0,          0, (2 * z_far * z_near) * nf, 0,
    };
}

pub fn vec3(x: f32, y: f32, z: f32) [3]f32 {
    return .{ x, y, z };
}

pub fn vsub(a: [3]f32, b: [3]f32) [3]f32 {
    return .{ a[0] - b[0], a[1] - b[1], a[2] - b[2] };
}
pub fn dot(a: [3]f32, b: [3]f32) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}
pub fn cross(a: [3]f32, b: [3]f32) [3]f32 {
    return .{
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    };
}

pub fn normalize(a: [3]f32) [3]f32 {
    const len = @sqrt(dot(a, a));
    return .{ a[0] / len, a[1] / len, a[2] / len };
}

// colonne-major
pub fn matrixLookAt(eye: [3]f32, target: [3]f32, up_hint: [3]f32) [16]f32 {
    const fwd = normalize(vsub(target, eye)); // +Z caméra (dans notre conv) → on va construire une base
    const right = normalize(cross(fwd, up_hint)); // +X
    const up = cross(right, fwd); // +Y
    // On veut une vue qui amène eye→origine et oriente axes monde vers axes caméra
    return .{
        right[0],         up[0],         -fwd[0],       0,
        right[1],         up[1],         -fwd[1],       0,
        right[2],         up[2],         -fwd[2],       0,
        -dot(right, eye), -dot(up, eye), dot(fwd, eye), 1,
    };
}

pub fn clampf(value: f32, min: f32, max: f32) f32 {
    return if (value < min) min else if (value > max) max else value;
}

pub fn deg2rad(angle: f32) f32 {
    return angle * (std.math.pi / 180.0);
}

pub fn add(a: [3]f32, b: [3]f32) [3]f32 {
    return .{ a[0] + b[0], a[1] + b[1], a[2] + b[2] };
}

pub fn sub(a: [3]f32, b: [3]f32) [3]f32 {
    return .{ a[0] - b[0], a[1] - b[1], a[2] - b[2] };
}

pub fn scale(a: [3]f32, s: f32) [3]f32 {
    return .{ a[0] * s, a[1] * s, a[2] * s };
}

pub fn mat4Inverse(m: [16]f32) [16]f32 {
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
    return out;
}

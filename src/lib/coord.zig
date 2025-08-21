const std = @import("std");
const wgpu = @import("./shared/wgpu.zig");
const math = @import("./math.zig");

// region Coord.Structs
pub const Vec2 = extern struct {
    x: f32,
    y: f32,

    pub fn init(x: f32, y: f32) Vec2 {
        return Vec2{ .x = x, .y = y };
    }
};

pub const Vec3 = extern struct {
    x: f32,
    y: f32,
    z: f32,

    pub const ZERO = Vec3.init(0, 0, 0);
    pub const ONE = Vec3.init(1, 1, 1);
    pub const UP = Vec3.init(0, 1, 0);

    pub fn init(x: f32, y: f32, z: f32) Vec3 {
        return Vec3{ .x = x, .y = y, .z = z };
    }

    pub fn toFloat32Array(self: *const Vec3) [3]f32 {
        return .{ self.x, self.y, self.z };
    }
};

pub const Rotator = extern struct {
    yaw: f32,
    pitch: f32,
    roll: f32,

    pub fn init(yaw: f32, pitch: f32, roll: f32) Rotator {
        return Rotator{ .yaw = yaw, .pitch = pitch, .roll = roll };
    }
};

pub const Vertex = extern struct {
    position: Vec3,
    uv: Vec2,
    normal: Vec3,

    pub fn init(position: Vec3, uv: Vec2, normal: Vec3) Vertex {
        return Vertex{ .position = position, .uv = uv, .normal = normal };
    }
};

pub const VertexFormat = enum {
    float32x2,
    float32x3,
};

pub const VertexAttribute = struct {
    location: u32,
    offset: u64,
    format: VertexFormat,
};

pub const VertexStepMode = enum {
    instance,
    vertex,
    vertex_buffer_not_used,
};

pub const VertexBufferLayoutDescriptor = struct {
    stride: u64,
    step_mode: VertexStepMode = .vertex,
    attrs: []const VertexAttribute,
};

pub const VertexBufferLayout = struct {
    _v: wgpu.WGPUVertexBufferLayout,
};
// endregion

// region Coord.Functions
pub fn createVertexBufferLayout(descriptor: VertexBufferLayoutDescriptor) !VertexBufferLayout {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    var tmp = try aa.alloc(wgpu.WGPUVertexAttribute, descriptor.attrs.len);
    for (descriptor.attrs, 0..) |attr, i| {
        tmp[i] = wgpu.WGPUVertexAttribute{
            .format = mapVertexFormat(attr.format),
            .offset = attr.offset,
            .shaderLocation = attr.location,
        };
    }

    return VertexBufferLayout{
        ._v = .{
            .arrayStride = descriptor.stride,
            .stepMode = mapVertexStepMode(descriptor.step_mode),
            .attributeCount = @intCast(descriptor.attrs.len),
            .attributes = tmp.ptr,
        },
    };
}
// endregion

// region Coord.helpers
pub fn mapVertexFormat(vertex_format: VertexFormat) wgpu.WGPUVertexFormat {
    return switch (vertex_format) {
        .float32x2 => wgpu.WGPUVertexFormat_Float32x2,
        .float32x3 => wgpu.WGPUVertexFormat_Float32x3,
    };
}

pub fn mapVertexStepMode(step_mode: VertexStepMode) wgpu.WGPUVertexStepMode {
    return switch (step_mode) {
        .instance => wgpu.WGPUVertexStepMode_Instance,
        .vertex => wgpu.WGPUVertexStepMode_Vertex,
        .vertex_buffer_not_used => wgpu.WGPUVertexStepMode_VertexBufferNotUsed,
    };
}
// endregion

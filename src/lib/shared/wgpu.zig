const c = @cImport({
    @cDefine("GLFW_INCLUDE_NONE", "1");
    @cDefine("GLFW_EXPOSE_NATIVE_COCOA", "1");
    @cDefine("WEBGPU_BACKEND_WGPU", "1");

    @cInclude("GLFW/glfw3.h");
    @cInclude("webgpu/wgpu.h");
    @cInclude("glfw3webgpu.h");
});

pub usingnamespace c;

pub inline fn svTolice(sv: c.WGPUStringView) []const u8 {
    if (sv.data == null or sv.length == 0) return &.{};
    return sv.data[0..@intCast(sv.length)];
}

pub inline fn sliceToSv(slice: [:0]const u8) c.WGPUStringView {
    return c.WGPUStringView{ .data = slice.ptr, .length = slice.len };
}

pub inline fn wb(b: bool) c.WGPUBool {
    return if (b) @as(c.WGPUBool, 1) else @as(c.WGPUBool, 0);
}

const std = @import("std");
const wgpu = @import("./shared/wgpu.zig");
const core_window = @import("./core/window.zig");

pub usingnamespace core_window;

// region Core.Aliases
const SV = wgpu.WGPUStringView;
// endregion

// region Core.Structs
pub const Instance = struct {
    _i: wgpu.WGPUInstance,
    pub fn destroy(self: *Instance) void {
        wgpu.wgpuInstanceRelease(self._i);
    }
};

pub const Surface = struct {
    _s: wgpu.WGPUSurface,
    pub fn destroy(self: *Surface) void {
        wgpu.wgpuSurfaceRelease(self._s);
    }
};

pub const Adapter = struct {
    _a: wgpu.WGPUAdapter,
    pub fn destroy(self: *Adapter) void {
        wgpu.wgpuAdapterRelease(self._a);
    }
};

pub const Device = struct {
    _d: wgpu.WGPUDevice,
    pub fn destroy(self: *Device) void {
        wgpu.wgpuDeviceRelease(self._d);
    }
};

pub const Queue = struct {
    _q: wgpu.WGPUQueue,
    pub fn destroy(self: *Queue) void {
        wgpu.wgpuQueueRelease(self._q);
    }
};

pub const SurfaceConfiguration = struct {
    _sc: wgpu.WGPUSurfaceConfiguration,
};

pub const Texture = struct {
    _t: wgpu.WGPUTexture,
    _v: wgpu.WGPUTextureView,
    _f: wgpu.WGPUTextureFormat,
    width: u32,
    height: u32,

    pub fn destroy(self: Texture) void {
        wgpu.wgpuTextureViewRelease(self._v);
        wgpu.wgpuTextureRelease(self._t);
    }
};

pub const Buffer = struct {
    _b: wgpu.WGPUBuffer,

    pub fn destroy(self: *Buffer) void {
        wgpu.wgpuBufferRelease(self._b);
    }
};
// endregion

// region Core.Functions
pub fn terminateGLFW() void {
    wgpu.glfwTerminate();
}

pub fn pollEvents() void {
    wgpu.glfwPollEvents();
}

pub fn createWindow(alloc: std.mem.Allocator, width: i32, height: i32, title: [:0]const u8, fullscreen: bool) !core_window.Window {
    if (wgpu.glfwInit() == 0) return error.GLFWInitFailed;

    var monitor: ?*wgpu.GLFWmonitor = null;
    var w: c_int = @intCast(width);
    var h: c_int = @intCast(height);
    if (fullscreen) {
        monitor = wgpu.glfwGetPrimaryMonitor();
        const mode = wgpu.glfwGetVideoMode(monitor);
        w = mode.*.width;
        h = mode.*.height;
    }

    wgpu.glfwWindowHint(wgpu.GLFW_CLIENT_API, wgpu.GLFW_NO_API);
    const window = wgpu.glfwCreateWindow(w, h, title, monitor, null);

    if (window == null) return error.WindowCreationFailed;

    return core_window.Window.init(alloc, window.?);
}

pub fn createInstance() !Instance {
    const instance = wgpu.wgpuCreateInstance(&.{});
    if (instance == null) return error.InstanceCreationFailed;

    return Instance{ ._i = instance.? };
}

pub fn createWindowSurface(instance: Instance, window: core_window.Window) !Surface {
    const surface = wgpu.glfwCreateWindowWGPUSurface(instance._i, window._w);
    if (surface == null) return error.SurfaceCreationFailed;

    return Surface{ ._s = surface.? };
}

pub fn requestAdapter(instance: Instance, surface: Surface) Adapter {
    var adapter: wgpu.WGPUAdapter = null;
    const options = wgpu.WGPURequestAdapterOptions{
        .powerPreference = wgpu.WGPUPowerPreference_HighPerformance,
        .compatibleSurface = surface._s,
    };
    const callback_info = wgpu.WGPURequestAdapterCallbackInfo{
        .mode = wgpu.WGPUCallbackMode_AllowProcessEvents,
        .userdata1 = @ptrCast(&adapter),
        .callback = onRequestAdapter,
    };

    _ = wgpu.wgpuInstanceRequestAdapter(instance._i, &options, callback_info);
    while (adapter == null) {
        wgpu.wgpuInstanceProcessEvents(instance._i);
    }

    return Adapter{ ._a = adapter.? };
}

pub fn requestDevice(instance: Instance, adapter: Adapter) Device {
    var device: wgpu.WGPUDevice = null;
    const desc = wgpu.WGPUDeviceDescriptor{
        .uncapturedErrorCallbackInfo = wgpu.WGPUUncapturedErrorCallbackInfo{
            .callback = onDeviceError,
        },
    };
    const callback_info = wgpu.WGPURequestDeviceCallbackInfo{
        .mode = wgpu.WGPUCallbackMode_AllowProcessEvents,
        .userdata1 = @ptrCast(&device),
        .callback = onRequestDevice,
    };

    _ = wgpu.wgpuAdapterRequestDevice(adapter._a, &desc, callback_info);
    while (device == null) {
        wgpu.wgpuInstanceProcessEvents(instance._i);
    }

    return Device{ ._d = device.? };
}

pub fn getDeviceQueue(device: Device) !Queue {
    const queue = wgpu.wgpuDeviceGetQueue(device._d);
    if (queue == null) return error.DeviceQueueFailed;

    return Queue{ ._q = queue };
}

pub fn getSurfaceConfiguration(window: core_window.Window, adapter: Adapter, device: Device, surface: Surface) SurfaceConfiguration {
    const fb_size = window.getFrameBufferSize();

    var caps = std.mem.zeroes(wgpu.WGPUSurfaceCapabilities);
    _ = wgpu.wgpuSurfaceGetCapabilities(surface._s, adapter._a, &caps);

    const surface_format = getSurfaceFormat(caps);
    const surface_configuration = wgpu.WGPUSurfaceConfiguration{
        .device = device._d,
        .format = surface_format,
        .usage = wgpu.WGPUTextureUsage_RenderAttachment,
        .presentMode = wgpu.WGPUPresentMode_Fifo,
        .alphaMode = wgpu.WGPUCompositeAlphaMode_Auto,
        .width = @intCast(@max(fb_size.width, 1)),
        .height = @intCast(@max(fb_size.height, 1)),
    };

    return SurfaceConfiguration{ ._sc = surface_configuration };
}

pub fn configureSurface(surface: Surface, surface_configuration: SurfaceConfiguration) void {
    wgpu.wgpuSurfaceConfigure(surface._s, &surface_configuration._sc);
}

pub fn getSurfaceTexture(surface: Surface, surface_configuration: SurfaceConfiguration) ?Texture {
    var surface_texture = std.mem.zeroes(wgpu.WGPUSurfaceTexture);
    wgpu.wgpuSurfaceGetCurrentTexture(surface._s, &surface_texture);
    if (surface_texture.status != wgpu.WGPUSurfaceGetCurrentTextureStatus_SuccessOptimal) {
        return null;
    }

    const view = wgpu.wgpuTextureCreateView(surface_texture.texture, null);
    return Texture{
        ._t = surface_texture.texture,
        ._v = view,
        ._f = surface_configuration._sc.format,
        .width = surface_configuration._sc.width,
        .height = surface_configuration._sc.height,
    };
}

pub fn createVertexBuffer(device: *const Device, name: [:0]const u8, bytes: []const u8) !Buffer {
    const descriptor = wgpu.WGPUBufferDescriptor{
        .label = wgpu.sliceToSv(name),
        .usage = wgpu.WGPUBufferUsage_Vertex | wgpu.WGPUBufferUsage_CopyDst,
        .size = bytes.len,
        .mappedAtCreation = wgpu.wb(false),
    };

    return Buffer{ ._b = wgpu.wgpuDeviceCreateBuffer(device._d, &descriptor) };
}

pub fn createIndexBuffer(device: *const Device, name: [:0]const u8, bytes: []const u8) !Buffer {
    const descriptor = wgpu.WGPUBufferDescriptor{
        .label = wgpu.sliceToSv(name),
        .usage = wgpu.WGPUBufferUsage_Index | wgpu.WGPUBufferUsage_CopyDst,
        .size = bytes.len,
        .mappedAtCreation = wgpu.wb(false),
    };

    return Buffer{ ._b = wgpu.wgpuDeviceCreateBuffer(device._d, &descriptor) };
}

pub fn createUniformBuffer(device: *const Device, name: [:0]const u8, byte_len: usize) !Buffer {
    const descriptor = wgpu.WGPUBufferDescriptor{
        .label = wgpu.sliceToSv(name),
        .usage = wgpu.WGPUBufferUsage_Uniform | wgpu.WGPUBufferUsage_CopyDst,
        .size = byte_len,
        .mappedAtCreation = wgpu.wb(false),
    };

    return Buffer{ ._b = wgpu.wgpuDeviceCreateBuffer(device._d, &descriptor) };
}

pub fn writeBuffer(queue: Queue, buffer: Buffer, bytes: []const u8, offset: u64) void {
    wgpu.wgpuQueueWriteBuffer(queue._q, buffer._b, offset, bytes.ptr, bytes.len);
}
// endregion

// region Core.helpers
fn getSurfaceFormat(caps: wgpu.WGPUSurfaceCapabilities) wgpu.WGPUTextureFormat {
    var i: usize = 0;
    while (i < caps.formatCount) : (i += 1) {
        const f = caps.formats[i];
        if (f == wgpu.WGPUTextureFormat_BGRA8Unorm or f == wgpu.WGPUTextureFormat_RGBA8Unorm) {
            return f;
        }
    }
    return caps.formats[0];
}
// endregion

// region Core.callbacks
fn onRequestAdapter(s: wgpu.WGPURequestAdapterStatus, a: wgpu.WGPUAdapter, m: SV, out: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
    if (out) |o| {
        const slot: *?wgpu.WGPUAdapter = @alignCast(@ptrCast(o));
        slot.* = if (s == wgpu.WGPURequestAdapterStatus_Success) a else null;
    }
    const msg = wgpu.svTolice(m);
    if (msg.len != 0) {
        std.debug.print("Adapter Request: {s}\n", .{msg});
    }
}

fn onRequestDevice(s: wgpu.WGPURequestDeviceStatus, d: wgpu.WGPUDevice, m: SV, out: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
    if (out) |o| {
        const slot: *?wgpu.WGPUDevice = @alignCast(@ptrCast(o));
        slot.* = if (s == wgpu.WGPURequestDeviceStatus_Success) d else null;
    }
    const msg = wgpu.svTolice(m);
    if (msg.len != 0) {
        std.debug.print("Device Request: {s}\n", .{msg});
    }
}

fn onDeviceError(_: [*c]const wgpu.WGPUDevice, typ: wgpu.WGPUErrorType, msg: wgpu.WGPUStringView, _: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
    std.debug.print("WGPU Device Error [{d}]: {s}\n", .{ typ, wgpu.svTolice(msg) });
}
// endregion

const std = @import("std");
const wgpu = @import("./shared/wgpu.zig");
const nk = @import("./shared/nk.zig");
const core = @import("./core.zig");
const coord = @import("./coord.zig");
const render = @import("./render.zig");
const math = @import("./math.zig");
const camera_ns = @import("./camera.zig");

pub const CameraBinding = struct {
    ubo: core.Buffer,
    bgl: render.BindGroupLayout,
    bg: render.BindGroup,
};

pub const App = struct {
    allocator: std.mem.Allocator,
    window: core.Window,
    instance: core.Instance,
    surface: core.Surface,
    adapter: core.Adapter,
    device: core.Device,
    queue: core.Queue,
    surface_configuration: core.SurfaceConfiguration,
    frame_bg_info: render.BindGroupInfo,
    nk_render: render.NkRender,
    nuklear: nk.Nuklear,

    camera: ?*camera_ns.FlyCam = null,
    last_frame_time: ?i128 = null,

    // region App.InternalStructs
    pub const Camera = struct {
        position: coord.Vec3 = coord.Vec3.ZERO,
        target: coord.Vec3 = coord.Vec3.ZERO,
        up: coord.Vec3 = coord.Vec3.UP,

        fov_y_deg: f32 = 60.0,
        near: f32 = 0.1,
        far: f32 = 100.0,

        ubo: core.Buffer = .{ ._b = null },

        pub fn vp(self: Camera, fb_w: i32, fb_h: i32) [16]f32 {
            const aspect = @as(f32, @floatFromInt(fb_w)) / @as(f32, @floatFromInt(fb_h));

            const P = math.matrixPerspective(self.fov_y_deg, aspect, self.near, self.far);
            const V = math.matrixLookAt(
                self.position.toFloat32Array(),
                self.target.toFloat32Array(),
                self.up.toFloat32Array(),
            );
            return math.matrixMult(P, V);
        }

        pub fn update(self: *Camera, window: core.Window, queue: core.Queue) void {
            const fb = window.getFrameBufferSize();
            const vp_matrix = self.vp(fb.width, fb.height);

            const ubo_value = struct {
                matrix: [16]f32,
                position: [3]f32,
                _pad: f32 = 0.0,
            }{
                .matrix = vp_matrix,
                .position = self.position.toFloat32Array(),
            };

            core.writeBuffer(queue, self.ubo, std.mem.asBytes(&ubo_value), 0);
        }

        pub fn destroy(self: *Camera) void {
            self.ubo.destroy();
        }
    };
    // endregion

    // region App.Lifecycle
    pub fn init(allocator: std.mem.Allocator, title: [:0]const u8, size: core.Size, fullscreen: bool) !App {
        const window = try core.createWindow(allocator, size.width, size.height, title, fullscreen);
        const instance = try core.createInstance();
        const surface = try core.createWindowSurface(instance, window);
        const adapter = core.requestAdapter(instance, surface);
        const device = core.requestDevice(instance, adapter);
        const queue = try core.getDeviceQueue(device);

        const surface_configuration = core.getSurfaceConfiguration(window, adapter, device, surface);
        core.configureSurface(surface, surface_configuration);

        const nuklear = try nk.Nuklear.init(&device, &queue);
        const frame_bg_info = try render.FrameRenderer.createFrameBinding(allocator, &device);
        const nk_render = try render.FrameRenderer.createNkRender(allocator, &device, surface_configuration._sc.format, nuklear.tex);

        return App{
            .allocator = allocator,
            .window = window,
            .instance = instance,
            .surface = surface,
            .adapter = adapter,
            .device = device,
            .queue = queue,
            .surface_configuration = surface_configuration,
            .frame_bg_info = frame_bg_info,
            .nuklear = nuklear,
            .nk_render = nk_render,
        };
    }

    pub fn destroy(self: *App) void {
        self.nk_render.destroy();
        self.nuklear.deinit();

        self.frame_bg_info.bg.destroy();
        self.frame_bg_info.bgl.destroy();

        self.queue.destroy();
        self.device.destroy();
        self.adapter.destroy();
        self.surface.destroy();
        self.instance.destroy();
        self.window.destroy();
        core.terminateGLFW();
    }
    // endregion

    pub fn setCamera(self: *App, camera: *camera_ns.FlyCam) !void {
        self.camera = camera;
        try camera.beginPlay(self);
    }

    pub fn getFrameRenderer(self: *App, frame: *render.FrameRenderer) bool {
        // Shift + Escape to close window
        const has_shift_pressed = self.window.hasInput(.left_shift, .press);
        const has_escape_pressed = self.window.hasInput(.escape, .press);
        if (has_shift_pressed and has_escape_pressed) {
            self.window.close();
        }

        // Handle window resize
        const fb_size = self.window.getFrameBufferSize();
        if (fb_size.width != self.surface_configuration._sc.width or fb_size.height != self.surface_configuration._sc.height) {
            self.surface_configuration._sc.width = @intCast(@max(fb_size.width, 1));
            self.surface_configuration._sc.height = @intCast(@max(fb_size.height, 1));

            core.configureSurface(self.surface, self.surface_configuration);
        }

        // Preparing frame renderer
        if (core.getSurfaceTexture(self.surface, self.surface_configuration)) |texture| {
            const global_time = std.time.nanoTimestamp();
            const render_context = render.RenderContext{
                .window = &self.window,
                .device = &self.device,
                .queue = &self.queue,
                .surface_texture = texture,
                .frame_bg_info = &self.frame_bg_info,
                .nuklear = &self.nuklear,
                .nk_render = &self.nk_render,

                .global_time = global_time,
                .delta_time = if (self.last_frame_time) |t| global_time - t else 0,
            };

            self.last_frame_time = global_time;
            frame.* = render.FrameRenderer.init(render_context, self.allocator);

            // Camera must be in the scene, not a App component
            if (self.camera) |camera| {
                camera.update(self.window, frame.render_context.getDeltaTime());

                const ubo_value = render.FrameUBO{
                    .vp = camera.vp,
                    .ivp = math.mat4Inverse(camera.vp),
                    .pos = camera.position,
                };

                if (self.frame_bg_info.bg.getBuffer(0)) |b| {
                    core.writeBuffer(self.queue, b, std.mem.asBytes(&ubo_value), 0);
                }
            }

            return true;
        }
        return false;
    }

    pub fn commitFrame(self: *App, frame: *render.FrameRenderer) void {
        const command = wgpu.wgpuCommandEncoderFinish(frame.encoder._e, null);
        wgpu.wgpuQueueSubmit(self.queue._q, 1, &command);
        _ = wgpu.wgpuSurfacePresent(self.surface._s);
        wgpu.wgpuCommandBufferRelease(command);
    }

    pub fn waitForNextFrame(_: *App) void {
        core.pollEvents();
    }
};

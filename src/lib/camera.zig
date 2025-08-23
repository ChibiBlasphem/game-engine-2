const std = @import("std");
const coord = @import("./coord.zig");
const core = @import("./core.zig");
const math = @import("./math.zig");
const wgpu = @import("./shared/wgpu.zig");
const app = @import("./app.zig");

pub const FlyCam = struct {
    owner: ?*app.App = null,

    position: math.f32x3,
    rotation: coord.Rotator,
    velocity: math.f32x3 = .init(.{ 0, 0, 0 }),

    captured: bool = false,
    first_mouse: bool = true,
    f1_pressed: bool = false,

    last_x: f64 = 0,
    last_y: f64 = 0,

    mouse_sens: f32 = 0.12,
    move_speed: f32 = 3.0,
    sprint_mul: f32 = 2.5,

    vp: math.mat4x4 = undefined,

    pub fn toggleCapture(self: *FlyCam, window: core.Window) void {
        self.captured = !self.captured;
        window.setCursorMode(if (self.captured) .disabled else .normal);
    }

    pub fn beginPlay(self: *FlyCam, owner: *app.App) !void {
        self.owner = owner;
        try owner.window.onInput(wgpu.GLFW_KEY_F1, .press, .{
            .listener = FlyCam.onPressF1,
            .userdata = @ptrCast(self),
        });
    }

    fn onPressF1(userdata: *anyopaque) void {
        const cam: *FlyCam = @ptrCast(@alignCast(userdata));
        cam.toggleCapture(cam.owner.?.window);
    }

    pub fn update(self: *FlyCam, window: core.Window, delta_time: f32) void {
        if (self.captured) {
            const mouse_pos = window.getMousePosition();
            if (self.first_mouse) {
                self.first_mouse = false;
            } else {
                const dx = @as(f32, @floatCast(mouse_pos.x - self.last_x));
                const dy = @as(f32, @floatCast(mouse_pos.y - self.last_y));

                self.rotation.yaw += dx * self.mouse_sens;
                self.rotation.pitch = math.clampf(self.rotation.pitch - dy * self.mouse_sens, -89.0, 89.0);
            }
            self.last_x = mouse_pos.x;
            self.last_y = mouse_pos.y;
        }

        // 2. Base axes
        const yaw = math.deg2rad(self.rotation.yaw);
        const pitch = math.deg2rad(self.rotation.pitch);

        const fwd = math.f32x3.init(.{
            @cos(pitch) * @cos(yaw),
            @sin(pitch),
            @cos(pitch) * @sin(yaw),
        }).normalize();

        const world_up = math.f32x3.init(.{ 0.0, 1.0, 0.0 });
        const right = fwd.cross(world_up).normalize();
        const up = right.cross(fwd).normalize();

        // 3. Keyboard movements
        var vel = self.move_speed;
        if (window.hasInput(wgpu.GLFW_KEY_LEFT_SHIFT, .press)) vel *= self.sprint_mul;

        const dv = vel * delta_time;
        if (window.hasInput(wgpu.GLFW_KEY_W, .press)) self.position = self.position.add(fwd.scale(dv));
        if (window.hasInput(wgpu.GLFW_KEY_S, .press)) self.position = self.position.sub(fwd.scale(dv));
        if (window.hasInput(wgpu.GLFW_KEY_A, .press)) self.position = self.position.sub(right.scale(dv));
        if (window.hasInput(wgpu.GLFW_KEY_D, .press)) self.position = self.position.add(right.scale(dv));

        if (window.hasInput(wgpu.GLFW_KEY_E, .press) or window.hasInput(wgpu.GLFW_KEY_SPACE, .press))
            self.position = self.position.add(world_up.scale(dv));
        if (window.hasInput(wgpu.GLFW_KEY_Q, .press) or window.hasInput(wgpu.GLFW_KEY_LEFT_CONTROL, .press))
            self.position = self.position.sub(world_up.scale(dv));

        // 4. VP
        const fb_size = window.getFrameBufferSize();
        const aspect = @as(f32, @floatFromInt(fb_size.width)) / @as(f32, @floatFromInt(fb_size.height));
        const P = math.mat4x4.perspective(90.0, aspect, 0.1, 500);
        const target = self.position.add(fwd);
        const V = math.mat4x4.lookAt(self.position, target, up);

        self.vp = P.mul(V);
    }
};

const std = @import("std");
const coord = @import("./coord.zig");
const core = @import("./core.zig");
const math = @import("./math.zig");
const wgpu = @import("./shared/wgpu.zig");

pub const FlyCam = struct {
    position: [3]f32,
    rotation: coord.Rotator,

    captured: bool = false,
    first_mouse: bool = true,
    f1_pressed: bool = false,

    last_x: f64 = 0,
    last_y: f64 = 0,

    mouse_sens: f32 = 0.12,
    move_speed: f32 = 3.0,
    sprint_mul: f32 = 2.5,

    vp: [16]f32 = undefined,

    pub fn toggleCapture(self: *FlyCam, window: core.Window) void {
        self.captured = !self.captured;
        window.setCursorMode(if (self.captured) .disabled else .normal);
    }

    pub fn update(self: *FlyCam, window: core.Window, delta_time: f32) void {
        if (window.hasInput(wgpu.GLFW_KEY_F1, .released) and self.f1_pressed) {
            std.debug.print("Has released F1\n", .{});
            self.toggleCapture(window);
        }
        self.f1_pressed = window.hasInput(wgpu.GLFW_KEY_F1, .press);

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

        var fwd: [3]f32 = .{
            std.math.cos(pitch) * std.math.cos(yaw),
            std.math.sin(pitch),
            std.math.cos(pitch) * std.math.sin(yaw),
        };
        fwd = math.normalize(fwd);

        const world_up = .{ 0.0, 1.0, 0.0 };
        const right = math.normalize(math.cross(fwd, world_up));
        const up = math.normalize(math.cross(right, fwd));

        // 3. Keyboard movements
        var vel = self.move_speed;
        if (window.hasInput(wgpu.GLFW_KEY_LEFT_SHIFT, .press)) vel *= self.sprint_mul;

        if (window.hasInput(wgpu.GLFW_KEY_W, .press)) self.position = math.add(self.position, math.scale(fwd, vel * delta_time));
        if (window.hasInput(wgpu.GLFW_KEY_S, .press)) self.position = math.sub(self.position, math.scale(fwd, vel * delta_time));
        if (window.hasInput(wgpu.GLFW_KEY_A, .press)) self.position = math.sub(self.position, math.scale(right, vel * delta_time));
        if (window.hasInput(wgpu.GLFW_KEY_D, .press)) self.position = math.add(self.position, math.scale(right, vel * delta_time));
        if (window.hasInput(wgpu.GLFW_KEY_E, .press) or window.hasInput(wgpu.GLFW_KEY_SPACE, .press))
            self.position = math.add(self.position, math.scale(world_up, vel * delta_time));
        if (window.hasInput(wgpu.GLFW_KEY_Q, .press) or window.hasInput(wgpu.GLFW_KEY_LEFT_CONTROL, .press))
            self.position = math.sub(self.position, math.scale(world_up, vel * delta_time));

        // 4. VP
        const fb_size = window.getFrameBufferSize();
        const aspect = @as(f32, @floatFromInt(fb_size.width)) / @as(f32, @floatFromInt(fb_size.height));
        const P = math.matrixPerspective(90.0, aspect, 0.1, 500);
        const target = math.add(self.position, fwd);
        const V = math.matrixLookAt(self.position, target, up);
        self.vp = math.matrixMult(P, V);
    }
};

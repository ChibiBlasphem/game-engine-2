const std = @import("std");
const wgpu = @import("../shared/wgpu.zig");
const input = @import("./input.zig");

pub const Size = struct {
    width: i32,
    height: i32,
};

pub const CursorMode = enum(c_int) {
    normal = std.zig.c_translation.promoteIntLiteral(c_int, 0x00034001, .hex),
    hidden = std.zig.c_translation.promoteIntLiteral(c_int, 0x00034002, .hex),
    disabled = std.zig.c_translation.promoteIntLiteral(c_int, 0x00034003, .hex),
    captured = std.zig.c_translation.promoteIntLiteral(c_int, 0x00034004, .hex),
    unavailable = std.zig.c_translation.promoteIntLiteral(c_int, 0x0001000B, .hex),
};

pub const KeyAction = enum(c_int) {
    released = 0,
    press = 1,
    repeat = 2,
};

pub const KeyListenerMapKey = struct {
    code: input.Keyboard,
    action: KeyAction,
};

pub const KeyListenerCallbackInfo = struct {
    listener: *const fn (userdata: *anyopaque) void,
    userdata: *anyopaque,
};

pub const Window = struct {
    const KLM = std.AutoHashMap(KeyListenerMapKey, std.ArrayList(KeyListenerCallbackInfo));

    _w: *wgpu.GLFWwindow,
    _a: std.mem.Allocator,
    _inputFun: ?wgpu.GLFWkeyfun = null,
    _keyListeners: KLM,

    pub fn init(alloc: std.mem.Allocator, window: *wgpu.GLFWwindow) !Window {
        return Window{
            ._w = window,
            ._a = alloc,
            ._keyListeners = KLM.init(alloc),
        };
    }

    pub fn destroy(self: *Window) void {
        var it = self._keyListeners.iterator();
        while (it.next()) |item| {
            item.value_ptr.*.deinit();
        }
        self._keyListeners.deinit();

        wgpu.glfwDestroyWindow(self._w);
    }

    pub fn close(self: *Window) void {
        wgpu.glfwSetWindowShouldClose(self._w, wgpu.GLFW_TRUE);
    }

    pub fn getFrameBufferSize(self: *const Window) Size {
        var fb_w: c_int = 0;
        var fb_h: c_int = 0;
        wgpu.glfwGetFramebufferSize(self._w, &fb_w, &fb_h);
        return Size{ .width = @intCast(fb_w), .height = @intCast(fb_h) };
    }

    pub fn getSize(self: *const Window) Size {
        var win_w: c_int = 0;
        var win_h: c_int = 0;
        wgpu.glfwGetWindowSize(self._w, &win_w, &win_h);
        return Size{ .width = @intCast(win_w), .height = @intCast(win_h) };
    }

    pub fn getMousePosition(self: *const Window) struct { x: f64, y: f64 } {
        var mx: f64 = 0;
        var my: f64 = 0;
        wgpu.glfwGetCursorPos(self._w, &mx, &my);

        return .{ .x = mx, .y = my };
    }

    pub fn shouldClose(self: *const Window) bool {
        return wgpu.glfwWindowShouldClose(self._w) != 0;
    }

    pub fn setCursorMode(self: *const Window, cursor_mode: CursorMode) void {
        wgpu.glfwSetInputMode(self._w, wgpu.GLFW_CURSOR, @intFromEnum(cursor_mode));
    }

    pub fn hasInput(self: *const Window, code: input.Keyboard, mode: KeyAction) bool {
        return wgpu.glfwGetKey(self._w, @intFromEnum(code)) == @intFromEnum(mode);
    }

    pub fn onInput(self: *Window, code: input.Keyboard, action: KeyAction, callback_info: KeyListenerCallbackInfo) !void {
        if (self._inputFun == null) {
            self._inputFun = wgpu.glfwSetKeyCallback(self._w, Window._handleInput);
            wgpu.glfwSetWindowUserPointer(self._w, self);
        }

        // Register a listener
        try self._registerKeyListener(code, action, callback_info);
    }

    fn _registerKeyListener(self: *Window, code: input.Keyboard, action: KeyAction, callback_info: KeyListenerCallbackInfo) !void {
        const key = KeyListenerMapKey{ .code = code, .action = action };
        const gop = try self._keyListeners.getOrPut(key);

        if (!gop.found_existing) {
            gop.value_ptr.* = std.ArrayList(KeyListenerCallbackInfo).init(self._a);
        }

        try gop.value_ptr.*.append(callback_info);
    }

    fn _handleInput(win: ?*wgpu.GLFWwindow, code: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.c) void {
        _ = scancode;
        _ = mods;

        const ptr = wgpu.glfwGetWindowUserPointer(win);
        if (ptr == null) return;
        const self: *Window = @ptrCast(@alignCast(ptr.?));

        const map_key = KeyListenerMapKey{ .code = @enumFromInt(code), .action = @enumFromInt(action) };
        if (self._keyListeners.get(map_key)) |listeners_info| {
            for (listeners_info.items) |listener_info| {
                listener_info.listener(listener_info.userdata);
            }
        }
    }
};

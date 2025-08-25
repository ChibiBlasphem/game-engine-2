const std = @import("std");
const mythopia = @import("mythopia");

pub fn main() !void {
    const b_show_grid: bool = true;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var app = try mythopia.App.init(alloc, "Hello WGPU", .{ .width = 1280, .height = 720 }, false);
    defer app.destroy();

    var camera = mythopia.camera.FlyCam{
        .position = .init(.{ 0, 1.5, 0 }),
        .rotation = mythopia.coord.Rotator.init(-90, 0, 0),
    };
    _ = try app.setCamera(&camera);

    while (!app.window.shouldClose()) {
        var frame: mythopia.render.FrameRenderer = undefined;
        if (app.getFrameRenderer(&frame)) {
            defer frame.destroy();

            var renderer3D = frame.beginRender3D(.{ 0, 0, 0, 1 });
            if (b_show_grid) {
                _ = try renderer3D.drawGrid();
            }
            renderer3D.commit();

            var renderer2D = frame.beginRender2D();
            frame.render_context.nuklear.demoWindow();
            try renderer2D.commit();

            // ui.newFrame();
            // ui.demoWindow();
            // ui.endFrame();

            // var renderer2D = frame.beginRender2D();
            // renderer2D.renderFPS() catch {};
            // renderer2D.addText("Hello world");

            // mythopia.imgui.igBegin(
            //     "Viewport tools",
            //     null,
            //     mythopia.imgui.ImGuiWindowFlagsZ_NoResize | mythopia.imgui.ImGuiWindowFlagsZ_NoMove | mythopia.imgui.ImGuiWindowFlagsZ_AlwaysAutoResize,
            // );
            // mythopia.imgui.igCheckbox("Show grid", &b_show_grid);
            // mythopia.imgui.igEnd();
            // renderer2D.commit();

            app.commitFrame(&frame);
        }

        app.waitForNextFrame();
    }

    // while (mythopia.experimental_wgpu.glfwWindowShouldClose(app.window._w) == 0) {
    //     // Manage resize
    //     const fb_size = window.getFrameBufferSize();
    //     if (fb_size.width != surface_configuration._sc.width or fb_size.height != surface_configuration._sc.height) {
    //         surface_configuration._sc.width = @intCast(@max(fb_size.width, 1));
    //         surface_configuration._sc.height = @intCast(@max(fb_size.height, 1));
    //         mythopia.experimental_wgpu.wgpuSurfaceConfigure(surface._s, &surface_configuration._sc);
    //     }

    //     var color_texture = std.mem.zeroes(mythopia.experimental_wgpu.WGPUSurfaceTexture);
    //     mythopia.experimental_wgpu.wgpuSurfaceGetCurrentTexture(surface._s, &color_texture);
    //     if (color_texture.status != mythopia.experimental_wgpu.WGPUSurfaceGetCurrentTextureStatus_SuccessOptimal) {
    //         mythopia.experimental_wgpu.wgpuSurfaceConfigure(surface._s, &surface_configuration._sc);
    //         mythopia.experimental_wgpu.glfwPollEvents();
    //         continue;
    //     }
    //     const color_view = mythopia.experimental_wgpu.wgpuTextureCreateView(color_texture.texture, null);

    //     _ = mythopia.experimental_wgpu.wgpuSurfacePresent(surface._s);

    //     mythopia.experimental_wgpu.wgpuTextureViewRelease(color_view);
    //     mythopia.experimental_wgpu.wgpuTextureRelease(color_texture.texture);

    //     mythopia.experimental_wgpu.glfwPollEvents();
    // }
}

const std = @import("std");
const wgpu = @import("./shared/wgpu.zig");
const imgui = @import("./shared/imgui.zig");
const core = @import("./core.zig");
const coord = @import("./coord.zig");
const math = @import("./math.zig");
const app = @import("./app.zig");
const wgsl = @embedFile("./shaders/grid.wgsl");

// region Render.Structs
pub const Shader = struct {
    _s: wgpu.WGPUShaderModule,

    pub fn destroy(self: *Shader) void {
        wgpu.wgpuShaderModuleRelease(self._s);
    }
};

pub const PrimitiveTopology = enum {
    triangles,
    triangle_strip,
    lines,
    line_strip,
    points,
};

pub const CullMode = enum {
    back,
    front,
    none,
};

pub const ShaderStage = enum {
    vertex,
    fragment,
    both,
};

pub const BindingType = union(enum) {
    uniform_buffer: struct { min_size: u64 = 0 },
};

pub const BindGroupLayoutEntry = struct {
    binding: u32,
    visibility: ShaderStage,
    b_type: BindingType,
};

pub const BindGroupLayout = struct {
    _l: wgpu.WGPUBindGroupLayout,

    pub fn destroy(self: *BindGroupLayout) void {
        wgpu.wgpuBindGroupLayoutRelease(self._l);
    }
};

pub const Binding = union(enum) {
    textureView: wgpu.WGPUTextureView,
    sampler: wgpu.WGPUSampler,
    buffer: struct { buf: core.Buffer, offset: u64 = 0, size: u64 },
};

pub const BindGroup = struct {
    _g: wgpu.WGPUBindGroup,
    _b: std.AutoHashMap(u32, core.Buffer),

    pub fn destroy(self: *BindGroup) void {
        var i = self._b.iterator();
        while (i.next()) |item| {
            item.value_ptr.*.destroy();
        }
        self._b.deinit();
        wgpu.wgpuBindGroupRelease(self._g);
    }

    pub fn getBuffer(self: *BindGroup, binding: u32) ?core.Buffer {
        return self._b.get(binding);
    }
};

pub const BindGroupInfo = struct {
    bgl: BindGroupLayout,
    bg: BindGroup,
};

pub const PipelineDescriptor = struct {
    name: [:0]const u8,
    shader: Shader,
    vertex_layout: ?coord.VertexBufferLayoutDescriptor = null,
    primitive: struct {
        topology: PrimitiveTopology,
        cull_mode: CullMode,
    },
    bind_group_layouts: []const BindGroupLayout,
};

pub const Pipeline = struct {
    _p: wgpu.WGPURenderPipeline,

    pub fn destroy(self: *Pipeline) void {
        wgpu.wgpuRenderPipelineRelease(self._p);
    }
};

pub const Encoder = struct {
    _e: wgpu.WGPUCommandEncoder,
    pub fn destroy(self: *Encoder) void {
        wgpu.wgpuCommandEncoderRelease(self._e);
    }
};

pub const RenderPass = struct {
    _p: wgpu.WGPURenderPassEncoder,

    pub fn destroy(self: *RenderPass) void {
        wgpu.wgpuRenderPassEncoderRelease(self._p);
    }

    pub fn end(self: *RenderPass) void {
        wgpu.wgpuRenderPassEncoderEnd(self._p);
    }
};

pub const FrameUBO = extern struct {
    vp: math.mat4x4,
    ivp: math.mat4x4,
    pos: math.f32x3,
};

pub const Renderer3D = struct {
    frame: *const FrameRenderer,
    pass: RenderPass,

    // region Renderer3D.Lifecycle
    pub fn init(frame: *const FrameRenderer, clear_color: [4]f32) Renderer3D {
        var color_attachment = wgpu.WGPURenderPassColorAttachment{
            .view = frame.render_context.surface_texture._v,
            .resolveTarget = null,
            .clearValue = .{ .r = clear_color[0], .g = clear_color[1], .b = clear_color[2], .a = clear_color[3] },
            .loadOp = wgpu.WGPULoadOp_Clear,
            .storeOp = wgpu.WGPUStoreOp_Store,
        };
        var descriptor = wgpu.WGPURenderPassDescriptor{
            .label = wgpu.sliceToSv("Renderer 3D"),
            .colorAttachmentCount = 1,
            .colorAttachments = &color_attachment,
        };

        const pass = wgpu.wgpuCommandEncoderBeginRenderPass(frame.encoder._e, &descriptor);

        return Renderer3D{
            .frame = frame,
            .pass = RenderPass{
                ._p = pass,
            },
        };
    }

    pub fn commit(self: *Renderer3D) void {
        self.pass.end();
        self.pass.destroy();
    }
    // endregion

    pub fn drawGrid(self: *Renderer3D) !void {
        const frame_bg_info = self.frame.render_context.frame_bg_info;

        const descriptor = PipelineDescriptor{
            .name = "Grid Pipeline",
            .shader = createShader(self.frame.render_context.device, wgsl),
            .bind_group_layouts = &.{
                frame_bg_info.bgl,
            },
            .primitive = .{
                .topology = .triangle_strip,
                .cull_mode = .none,
            },
        };

        const pipeline = try createPipeline(self.frame.render_context.device, &self.frame.render_context.surface_texture, descriptor);
        wgpu.wgpuRenderPassEncoderSetPipeline(self.pass._p, pipeline._p);
        wgpu.wgpuRenderPassEncoderSetBindGroup(self.pass._p, 0, frame_bg_info.bg._g, 0, null);

        wgpu.wgpuRenderPassEncoderDraw(self.pass._p, 4, 1, 0, 0);
    }
};

pub const Renderer2D = struct {
    frame: *const FrameRenderer,
    pass: RenderPass,

    // region Renderer2D.Lifecycle
    pub fn init(frame: *const FrameRenderer) Renderer2D {
        var color_attachment = wgpu.WGPURenderPassColorAttachment{
            .view = frame.render_context.surface_texture._v,
            .loadOp = wgpu.WGPULoadOp_Load,
            .storeOp = wgpu.WGPUStoreOp_Store,
        };

        var descriptor = wgpu.WGPURenderPassDescriptor{
            .label = wgpu.sliceToSv("Renderer 2D"),
            .colorAttachmentCount = 1,
            .colorAttachments = &color_attachment,
        };

        imgui.igNewFrameWgpu();
        imgui.igNewFrameGlfw();
        imgui.igNewFrame();

        const pass = wgpu.wgpuCommandEncoderBeginRenderPass(frame.encoder._e, &descriptor);

        return Renderer2D{ .frame = frame, .pass = RenderPass{
            ._p = pass,
        } };
    }

    pub fn commit(self: *Renderer2D) void {
        imgui.igRender();
        imgui.igRenderDrawData(self.pass._p);
        self.pass.end();
        self.pass.destroy();
    }
    // endregion

    pub fn renderFPS(self: *Renderer2D) !void {
        var a = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer a.deinit();
        const aa = a.allocator();

        const dt = self.frame.render_context.getDeltaTime();
        const fps = try std.fmt.allocPrintZ(aa, "{d:.2}", .{if (dt == 0) 0 else 1 / dt});

        imgui.igBegin("FPS", null, imgui.ImGuiWindowFlagsZ_None);
        imgui.igText(fps);
        imgui.igEnd();
    }

    pub fn addText(_: *Renderer2D, text: [:0]const u8) void {
        imgui.igBegin("Debug", null, imgui.ImGuiWindowFlagsZ_None);
        imgui.igText(text);
        imgui.igEnd();
    }
};

pub const RenderContext = struct {
    device: *const core.Device,
    queue: *const core.Queue,
    surface_texture: core.Texture,
    frame_bg_info: *const BindGroupInfo,

    global_time: i128,
    delta_time: i128,

    pub fn getDeltaTime(self: *const RenderContext) f32 {
        return @as(f32, @floatFromInt(self.delta_time)) / @as(f32, @floatFromInt(std.time.ns_per_s));
    }
};

pub const FrameRenderer = struct {
    render_context: RenderContext,
    encoder: Encoder,

    // region RenderFrame.Lifecycle
    pub fn init(render_context: RenderContext) FrameRenderer {
        const encoder = wgpu.wgpuDeviceCreateCommandEncoder(render_context.device._d, &.{});

        return FrameRenderer{
            .render_context = render_context,
            .encoder = Encoder{ ._e = encoder },
        };
    }

    pub fn destroy(self: *FrameRenderer) void {
        self.encoder.destroy();
    }
    // endregion

    pub fn createFrameBinding(allocator: std.mem.Allocator, device: core.Device) !BindGroupInfo {
        const buffer = try core.createUniformBuffer(&device, @sizeOf(FrameUBO));
        const bgl = try createBindGroupLayout(&device, FRAME_BGL[0..]);
        const bg = try createBindGroup(allocator, &device, bgl, &[_]Binding{
            Binding{ .buffer = .{ .buf = buffer, .size = @sizeOf(FrameUBO) } },
        });

        return BindGroupInfo{ .bgl = bgl, .bg = bg };
    }

    pub fn beginRender3D(self: *const FrameRenderer, clear_color: [4]f32) Renderer3D {
        return Renderer3D.init(self, clear_color);
    }

    pub fn beginRender2D(self: *const FrameRenderer) Renderer2D {
        return Renderer2D.init(self);
    }
};
// endregion

// region Render.Constants
const FRAME_BGL = [_]BindGroupLayoutEntry{
    BindGroupLayoutEntry{ .binding = 0, .visibility = .both, .b_type = .{ .uniform_buffer = .{ .min_size = @sizeOf(FrameUBO) } } },
};
// endregion

// region Render.Functions
pub fn createShader(device: *const core.Device, code: [:0]const u8) Shader {
    var wgslDesc: wgpu.WGPUShaderSourceWGSL = .{
        .chain = .{ .next = null, .sType = wgpu.WGPUSType_ShaderSourceWGSL },
        .code = wgpu.sliceToSv(code),
    };
    var shaderDesc: wgpu.WGPUShaderModuleDescriptor = .{
        .nextInChain = &wgslDesc.chain,
    };
    return .{ ._s = wgpu.wgpuDeviceCreateShaderModule(device._d, &shaderDesc) };
}

pub fn createPipeline(device: *const core.Device, texture: *const core.Texture, descriptor: PipelineDescriptor) !Pipeline {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    var vertex_state = wgpu.WGPUVertexState{
        .module = descriptor.shader._s,
        .entryPoint = wgpu.sliceToSv("vs_main"),
        .bufferCount = 0,
    };

    if (descriptor.vertex_layout) |vertex_layout| {
        var tmp = try aa.alloc(wgpu.WGPUVertexAttribute, vertex_layout.attrs.len);
        for (vertex_layout.attrs, 0..) |attr, i| {
            tmp[i] = wgpu.WGPUVertexAttribute{
                .format = coord.mapVertexFormat(attr.format),
                .offset = attr.offset,
                .shaderLocation = attr.location,
            };
        }

        const buffer: wgpu.WGPUVertexBufferLayout = .{
            .arrayStride = vertex_layout.stride,
            .stepMode = coord.mapVertexStepMode(vertex_layout.step_mode),
            .attributeCount = @intCast(vertex_layout.attrs.len),
            .attributes = tmp.ptr,
        };
        var buffers: [1]wgpu.WGPUVertexBufferLayout = .{buffer};

        vertex_state.bufferCount = 1;
        vertex_state.buffers = &buffers;
    }

    const blend_state = wgpu.WGPUBlendState{
        .color = .{
            .srcFactor = wgpu.WGPUBlendFactor_SrcAlpha,
            .dstFactor = wgpu.WGPUBlendFactor_OneMinusSrcAlpha,
            .operation = wgpu.WGPUBlendOperation_Add,
        },
        .alpha = .{
            .srcFactor = wgpu.WGPUBlendFactor_One,
            .dstFactor = wgpu.WGPUBlendFactor_OneMinusSrcAlpha,
            .operation = wgpu.WGPUBlendOperation_Add,
        },
    };

    const fragment_state = wgpu.WGPUFragmentState{
        .module = descriptor.shader._s,
        .entryPoint = wgpu.sliceToSv("fs_main"),
        .targetCount = 1,
        .targets = &wgpu.WGPUColorTargetState{
            .format = texture._f,
            .writeMask = wgpu.WGPUColorWriteMask_All,
            .blend = &blend_state,
        },
    };

    // TODO: Depth state (depth?)
    var tmp2 = try aa.alloc(wgpu.WGPUBindGroupLayout, descriptor.bind_group_layouts.len);
    for (descriptor.bind_group_layouts, 0..) |bgl, i| {
        tmp2[i] = bgl._l;
    }

    const pipeline_layout_descriptor = wgpu.WGPUPipelineLayoutDescriptor{
        .bindGroupLayoutCount = @intCast(descriptor.bind_group_layouts.len),
        .bindGroupLayouts = tmp2.ptr,
    };
    const pipeline_layout = wgpu.wgpuDeviceCreatePipelineLayout(device._d, &pipeline_layout_descriptor);
    defer wgpu.wgpuPipelineLayoutRelease(pipeline_layout);

    const pipeline_descriptor = wgpu.WGPURenderPipelineDescriptor{
        .label = wgpu.sliceToSv(descriptor.name),
        .vertex = vertex_state,
        .fragment = &fragment_state,
        .layout = pipeline_layout,
        .multisample = .{
            .count = 1,
            .mask = ~@as(u32, 0),
            .alphaToCoverageEnabled = wgpu.wb(false),
        },
        .primitive = wgpu.WGPUPrimitiveState{
            .cullMode = wgpu.WGPUCullMode_Undefined,
            // .cullMode = mapCullMode(descriptor.primitive.cull_mode),
            .frontFace = wgpu.WGPUFrontFace_Undefined,
            .stripIndexFormat = wgpu.WGPUIndexFormat_Undefined,
            .topology = mapPrimitiveTopology(descriptor.primitive.topology),
        },
    };

    return Pipeline{ ._p = wgpu.wgpuDeviceCreateRenderPipeline(device._d, &pipeline_descriptor) };
}

pub fn createBindGroupLayout(device: *const core.Device, entries: []const BindGroupLayoutEntry) !BindGroupLayout {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var tmp = try arena_allocator.alloc(wgpu.WGPUBindGroupLayoutEntry, entries.len);
    for (entries, 0..) |entry, i| {
        var wgpu_entry = std.mem.zeroes(wgpu.WGPUBindGroupLayoutEntry);
        wgpu_entry.binding = entry.binding;
        wgpu_entry.visibility = mapShaderStage(entry.visibility);

        switch (entry.b_type) {
            .uniform_buffer => |b| wgpu_entry.buffer = wgpu.WGPUBufferBindingLayout{
                .type = wgpu.WGPUBufferBindingType_Uniform,
                .hasDynamicOffset = 0,
                .minBindingSize = b.min_size,
            },
        }

        tmp[i] = wgpu_entry;
    }

    const bind_group_layout_descriptor = wgpu.WGPUBindGroupLayoutDescriptor{
        .entryCount = @intCast(entries.len),
        .entries = tmp.ptr,
    };

    return BindGroupLayout{ ._l = wgpu.wgpuDeviceCreateBindGroupLayout(device._d, &bind_group_layout_descriptor) };
}

pub fn createBindGroup(allocator: std.mem.Allocator, device: *const core.Device, layout: BindGroupLayout, bindings: []const Binding) !BindGroup {
    var tmp: [8]wgpu.WGPUBindGroupEntry = undefined;
    if (bindings.len > tmp.len) return error.TooManyBindings;

    var buffer_map = std.AutoHashMap(u32, core.Buffer).init(allocator);
    var i: u32 = 0;
    while (i < bindings.len) : (i += 1) {
        var e: wgpu.WGPUBindGroupEntry = std.mem.zeroes(wgpu.WGPUBindGroupEntry);
        e.binding = @intCast(i);

        switch (bindings[i]) {
            .textureView => |view| e.textureView = view,
            .sampler => |s| e.sampler = s,
            .buffer => |b| {
                e.buffer = b.buf._b;
                e.offset = b.offset;
                e.size = b.size;

                try buffer_map.put(i, b.buf);
            },
        }

        tmp[i] = e;
    }

    const description = wgpu.WGPUBindGroupDescriptor{
        .layout = layout._l,
        .entryCount = @intCast(bindings.len),
        .entries = &tmp,
    };

    return BindGroup{ ._g = wgpu.wgpuDeviceCreateBindGroup(device._d, &description), ._b = buffer_map };
}
// endregion

// region Render.helpers
pub fn mapPrimitiveTopology(topology: PrimitiveTopology) wgpu.WGPUPrimitiveTopology {
    return switch (topology) {
        .triangles => wgpu.WGPUPrimitiveTopology_TriangleList,
        .triangle_strip => wgpu.WGPUPrimitiveTopology_TriangleStrip,
        .lines => wgpu.WGPUPrimitiveTopology_LineList,
        .line_strip => wgpu.WGPUPrimitiveTopology_LineStrip,
        .points => wgpu.WGPUPrimitiveTopology_PointList,
    };
}

pub fn mapCullMode(cull_mode: CullMode) wgpu.WGPUCullMode {
    return switch (cull_mode) {
        .back => wgpu.WGPUCullMode_Back,
        .front => wgpu.WGPUCullMode_Front,
        .none => wgpu.WGPUCullMode_None,
    };
}

pub fn mapShaderStage(visibility: ShaderStage) wgpu.WGPUShaderStage {
    return switch (visibility) {
        .vertex => wgpu.WGPUShaderStage_Vertex,
        .fragment => wgpu.WGPUShaderStage_Fragment,
        .both => wgpu.WGPUShaderStage_Vertex | wgpu.WGPUShaderStage_Fragment,
    };
}
// endregion

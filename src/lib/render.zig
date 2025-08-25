const std = @import("std");
const wgpu = @import("./shared/wgpu.zig");
const nk = @import("./shared/nk.zig");
const core = @import("./core.zig");
const coord = @import("./coord.zig");
const math = @import("./math.zig");
const app = @import("./app.zig");
const grid_wgsl = @embedFile("./shaders/grid.wgsl");
const ui_wgsl = @embedFile("./shaders/ui.wgsl");

// region Render.Primitives
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

pub const FrontFace = enum {
    none,
    ccw,
    cw,
};

pub const IndexFormat = enum {
    none,
    uint16,
    uint32,
};

pub const ShaderStage = enum {
    vertex,
    fragment,
    both,
};

pub const BufferBindingType = enum {
    none,
    undefined,
    uniform,
    storage,
    readonly_storage,
};

pub const SamplerBindingType = enum {
    none,
    undefined,
    filtering,
    non_filtering,
    comparison,
};

pub const TextureSampleType = enum {
    none,
    undefined,
    float,
    unfilterable_float,
    depth,
    s_int,
    u_int,
};

pub const TextureViewDimension = enum {
    none,
    @"1d",
    @"2d",
    @"2d_array",
    cube,
    cube_array,
    @"3d",
};

pub const BindingType = union(enum) {
    buffer: struct {
        type: BufferBindingType,
        has_dynamic_offset: bool = false,
        min_size: u64 = 0,
    },
    sampler: struct { type: SamplerBindingType },
    texture: struct {
        sample_type: TextureSampleType,
        view_dimension: TextureViewDimension,
        multisampled: bool = false,
    },
};

pub const BindGroupLayoutEntry = struct {
    binding: u32,
    visibility: ShaderStage,
    type: BindingType,
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
        cull_mode: CullMode = .none,
        front_face: FrontFace = .ccw,
        strip_index_format: IndexFormat = .none,
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

pub const RenderContext = struct {
    window: *const core.Window,
    device: *const core.Device,
    queue: *const core.Queue,
    surface_texture: core.Texture,
    frame_bg_info: *const BindGroupInfo,
    nuklear: *nk.Nuklear,
    nk_render: *NkRender,

    global_time: i128,
    delta_time: i128,

    pub fn getDeltaTime(self: *const RenderContext) f32 {
        return @as(f32, @floatFromInt(self.delta_time)) / @as(f32, @floatFromInt(std.time.ns_per_s));
    }
};

pub const NkRender = struct {
    pipeline: Pipeline,
    bg_info: BindGroupInfo,
    surface_format: wgpu.WGPUTextureFormat, // ???

    pub fn destroy(self: *NkRender) void {
        self.pipeline.destroy();
        self.bg_info.bg.destroy();
        self.bg_info.bgl.destroy();
    }
};
// endregion

// region Render.Structs
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
            .shader = createShader(self.frame.render_context.device, grid_wgsl),
            .bind_group_layouts = &.{
                frame_bg_info.bgl,
            },
            .primitive = .{
                .topology = .triangle_strip,
                .cull_mode = .none,
            },
        };

        const surface_format = self.frame.render_context.surface_texture._f;
        const pipeline = try createPipeline(self.frame.render_context.device, surface_format, descriptor);
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
            .resolveTarget = null,
            .loadOp = wgpu.WGPULoadOp_Load,
            .storeOp = wgpu.WGPUStoreOp_Store,
        };
        var descriptor = wgpu.WGPURenderPassDescriptor{
            .label = wgpu.sliceToSv("Renderer 2D"),
            .colorAttachmentCount = 1,
            .colorAttachments = &color_attachment,
        };
        const pass = wgpu.wgpuCommandEncoderBeginRenderPass(frame.encoder._e, &descriptor);

        frame.render_context.nuklear.newFrame();

        return Renderer2D{
            .frame = frame,
            .pass = RenderPass{
                ._p = pass,
            },
        };
    }

    pub fn commit(self: *Renderer2D) !void {
        const draw_list = try self.frame.render_context.nuklear.build(self.frame.allocator);
        defer self.frame.allocator.free(draw_list.cmds);

        const nk_render = self.frame.render_context.nk_render;
        const fb_size = self.frame.render_context.window.getFrameBufferSize();
        // const win_size = self.frame.render_context.window.getSize();

        if (nk_render.bg_info.bg.getBuffer(2)) |ubo| {
            const vbuf = try core.createVertexBuffer(self.frame.render_context.device, "ui_vb", draw_list.vertices);
            const ibuf = try core.createIndexBuffer(self.frame.render_context.device, "ui_ib", draw_list.indices);

            wgpu.wgpuQueueWriteBuffer(self.frame.render_context.queue._q, vbuf._b, 0, draw_list.vertices.ptr, draw_list.vertices.len);
            wgpu.wgpuQueueWriteBuffer(self.frame.render_context.queue._q, ibuf._b, 0, draw_list.indices.ptr, draw_list.indices.len);

            var data: [4]f32 = .{ 2.0 / @as(f32, @floatFromInt(fb_size.width)), -2.0 / @as(f32, @floatFromInt(fb_size.height)), -1.0, 1.0 };

            // (si tu dessines en pixels "fenêtre", multiplie scale par sx/sy)
            wgpu.wgpuQueueWriteBuffer(self.frame.render_context.queue._q, ubo._b, 0, &data, @sizeOf(@TypeOf(data)));

            wgpu.wgpuRenderPassEncoderSetPipeline(self.pass._p, nk_render.pipeline._p);
            wgpu.wgpuRenderPassEncoderSetVertexBuffer(self.pass._p, 0, vbuf._b, 0, draw_list.vertices.len);
            wgpu.wgpuRenderPassEncoderSetIndexBuffer(self.pass._p, ibuf._b, wgpu.WGPUIndexFormat_Uint16, 0, draw_list.indices.len);
            wgpu.wgpuRenderPassEncoderSetBindGroup(self.pass._p, 0, nk_render.bg_info.bg._g, 0, null);

            // const sx: f32 = @as(f32, @floatFromInt(fb_size.width)) / @as(f32, @floatFromInt(win_size.width));
            // const sy: f32 = @as(f32, @floatFromInt(fb_size.height)) / @as(f32, @floatFromInt(win_size.height));

            for (draw_list.cmds) |cmd| {
                if (cmd.elem_count == 0) continue;

                const x: u32 = @intCast(math.clamp(cmd.clip_x, 0, fb_size.width));
                const y: u32 = @intCast(math.clamp(cmd.clip_y, 0, fb_size.height));
                const w: u32 = @intCast(math.clamp(@intCast(cmd.clip_w), 0, fb_size.width));
                const h: u32 = @intCast(math.clamp(@intCast(cmd.clip_h), 0, fb_size.height));

                wgpu.wgpuRenderPassEncoderSetScissorRect(self.pass._p, x, y, w, h);
                wgpu.wgpuRenderPassEncoderDrawIndexed(self.pass._p, cmd.elem_count, 1, cmd.index_offset, 0, 0);
            }
        }

        self.frame.render_context.nuklear.endFrame();
        self.pass.end();
        self.pass.destroy();
    }
    // endregion

    // pub fn renderFPS(_: *Renderer2D) !void {}

    // pub fn addText(_: *Renderer2D, _: [:0]const u8) void {}
};

pub const FrameRenderer = struct {
    allocator: std.mem.Allocator,
    render_context: RenderContext,
    encoder: Encoder,

    // region RenderFrame.Lifecycle
    pub fn init(render_context: RenderContext, allocator: std.mem.Allocator) FrameRenderer {
        const encoder = wgpu.wgpuDeviceCreateCommandEncoder(render_context.device._d, &.{});

        return FrameRenderer{
            .allocator = allocator,
            .render_context = render_context,
            .encoder = Encoder{ ._e = encoder },
        };
    }

    pub fn destroy(self: *FrameRenderer) void {
        self.encoder.destroy();
    }
    // endregion

    pub fn createFrameBinding(allocator: std.mem.Allocator, device: *const core.Device) !BindGroupInfo {
        const buffer = try core.createUniformBuffer(device, "frame_ubo", @sizeOf(FrameUBO));
        const bgl = try createBindGroupLayout(device, "frame_bgl", FRAME_BGL[0..]);
        const bg = try createBindGroup(allocator, "frame_bg", device, bgl, &[_]Binding{
            Binding{ .buffer = .{ .buf = buffer, .size = @sizeOf(FrameUBO) } },
        });

        return BindGroupInfo{ .bgl = bgl, .bg = bg };
    }

    pub fn createNkRender(allocator: std.mem.Allocator, device: *const core.Device, surface_format: wgpu.WGPUTextureFormat, font: nk.NkTex) !NkRender {
        const binding_size: usize = 4 * @sizeOf(f32);
        const buf = try core.createUniformBuffer(device, "nk_ubo", binding_size);
        const bgl = try createBindGroupLayout(device, "nk_bgl", &[_]BindGroupLayoutEntry{
            BindGroupLayoutEntry{ .binding = 0, .visibility = .fragment, .type = .{ .sampler = .{ .type = .filtering } } },
            BindGroupLayoutEntry{ .binding = 1, .visibility = .fragment, .type = .{ .texture = .{ .sample_type = .float, .view_dimension = .@"2d", .multisampled = false } } },
            BindGroupLayoutEntry{ .binding = 2, .visibility = .vertex, .type = .{ .buffer = .{ .type = .uniform, .min_size = binding_size } } },
        });
        const bg = try createBindGroup(allocator, "nk_bg", device, bgl, &[_]Binding{
            Binding{ .sampler = font.samp },
            Binding{ .textureView = font.view },
            Binding{ .buffer = .{ .buf = buf, .size = binding_size } },
        });
        const shader = createShader(device, ui_wgsl);

        const pipeline_descriptor = PipelineDescriptor{
            .name = "NK Pipeline",
            .shader = shader,
            .vertex_layout = coord.VertexBufferLayoutDescriptor{
                .stride = 20,
                .step_mode = .vertex,
                .attrs = &[_]coord.VertexAttribute{
                    coord.VertexAttribute{ .location = 0, .format = .float32x2, .offset = 0 },
                    coord.VertexAttribute{ .location = 1, .format = .float32x2, .offset = 8 },
                    coord.VertexAttribute{ .location = 2, .format = .unorm8x4, .offset = 16 },
                },
            },
            .primitive = .{
                .topology = .triangles,
                .front_face = .cw,
            },
            .bind_group_layouts = &[_]BindGroupLayout{bgl},
        };
        const pipeline = try createPipeline(device, surface_format, pipeline_descriptor);

        return NkRender{
            .pipeline = pipeline,
            .bg_info = BindGroupInfo{
                .bg = bg,
                .bgl = bgl,
            },
            .surface_format = surface_format,
        };
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
    BindGroupLayoutEntry{ .binding = 0, .visibility = .both, .type = .{ .buffer = .{ .type = .uniform, .min_size = @sizeOf(FrameUBO) } } },
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

pub fn createPipeline(device: *const core.Device, surface_format: wgpu.WGPUTextureFormat, descriptor: PipelineDescriptor) !Pipeline {
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
            .format = surface_format,
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
            .cullMode = mapCullMode(descriptor.primitive.cull_mode),
            .frontFace = mapFrontFace(descriptor.primitive.front_face),
            .stripIndexFormat = mapIndexFormat(descriptor.primitive.strip_index_format),
            .topology = mapPrimitiveTopology(descriptor.primitive.topology),
        },
    };

    return Pipeline{ ._p = wgpu.wgpuDeviceCreateRenderPipeline(device._d, &pipeline_descriptor) };
}

pub fn createBindGroupLayout(device: *const core.Device, name: [:0]const u8, entries: []const BindGroupLayoutEntry) !BindGroupLayout {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var tmp = try arena_allocator.alloc(wgpu.WGPUBindGroupLayoutEntry, entries.len);
    for (entries, 0..) |entry, i| {
        var wgpu_entry = std.mem.zeroes(wgpu.WGPUBindGroupLayoutEntry);
        wgpu_entry.binding = entry.binding;
        wgpu_entry.visibility = mapShaderStage(entry.visibility);

        switch (entry.type) {
            .buffer => |b| wgpu_entry.buffer = wgpu.WGPUBufferBindingLayout{
                .type = mapBufferBindingType(b.type),
                .hasDynamicOffset = wgpu.wb(b.has_dynamic_offset),
                .minBindingSize = b.min_size,
            },
            .texture => |t| wgpu_entry.texture = wgpu.WGPUTextureBindingLayout{
                .sampleType = mapSampleType(t.sample_type),
                .viewDimension = mapTextureViewDimension(t.view_dimension),
                .multisampled = wgpu.wb(t.multisampled),
            },
            .sampler => |s| wgpu_entry.sampler = wgpu.WGPUSamplerBindingLayout{
                .type = mapSamplerBindingType(s.type),
            },
        }

        tmp[i] = wgpu_entry;
    }

    const bind_group_layout_descriptor = wgpu.WGPUBindGroupLayoutDescriptor{
        .label = wgpu.sliceToSv(name),
        .entryCount = @intCast(entries.len),
        .entries = tmp.ptr,
    };

    return BindGroupLayout{ ._l = wgpu.wgpuDeviceCreateBindGroupLayout(device._d, &bind_group_layout_descriptor) };
}

pub fn createBindGroup(allocator: std.mem.Allocator, name: [:0]const u8, device: *const core.Device, layout: BindGroupLayout, bindings: []const Binding) !BindGroup {
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
        .label = wgpu.sliceToSv(name),
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

pub fn mapFrontFace(front_face: FrontFace) wgpu.WGPUFrontFace {
    return switch (front_face) {
        .none => wgpu.WGPUFrontFace_Undefined,
        .ccw => wgpu.WGPUFrontFace_CCW,
        .cw => wgpu.WGPUFrontFace_CW,
    };
}

pub fn mapIndexFormat(index_format: IndexFormat) wgpu.WGPUIndexFormat {
    return switch (index_format) {
        .none => wgpu.WGPUIndexFormat_Undefined,
        .uint16 => wgpu.WGPUIndexFormat_Uint16,
        .uint32 => wgpu.WGPUIndexFormat_Uint32,
    };
}

pub fn mapShaderStage(visibility: ShaderStage) wgpu.WGPUShaderStage {
    return switch (visibility) {
        .vertex => wgpu.WGPUShaderStage_Vertex,
        .fragment => wgpu.WGPUShaderStage_Fragment,
        .both => wgpu.WGPUShaderStage_Vertex | wgpu.WGPUShaderStage_Fragment,
    };
}

pub fn mapBufferBindingType(bbt: BufferBindingType) wgpu.WGPUBufferBindingType {
    return switch (bbt) {
        .none => wgpu.WGPUBufferBindingType_BindingNotUsed,
        .undefined => wgpu.WGPUBufferBindingType_Undefined,
        .uniform => wgpu.WGPUBufferBindingType_Uniform,
        .storage => wgpu.WGPUBufferBindingType_Storage,
        .readonly_storage => wgpu.WGPUBufferBindingType_ReadOnlyStorage,
    };
}

pub fn mapSamplerBindingType(sbt: SamplerBindingType) wgpu.WGPUSamplerBindingType {
    return switch (sbt) {
        .none => wgpu.WGPUSamplerBindingType_BindingNotUsed,
        .undefined => wgpu.WGPUSamplerBindingType_Undefined,
        .filtering => wgpu.WGPUSamplerBindingType_Filtering,
        .non_filtering => wgpu.WGPUSamplerBindingType_NonFiltering,
        .comparison => wgpu.WGPUSamplerBindingType_Comparison,
    };
}

pub fn mapSampleType(sample_type: TextureSampleType) wgpu.WGPUTextureSampleType {
    return switch (sample_type) {
        .none => wgpu.WGPUTextureSampleType_BindingNotUsed,
        .undefined => wgpu.WGPUTextureSampleType_Undefined,
        .float => wgpu.WGPUTextureSampleType_Float,
        .unfilterable_float => wgpu.WGPUTextureSampleType_UnfilterableFloat,
        .depth => wgpu.WGPUTextureSampleType_Depth,
        .s_int => wgpu.WGPUTextureSampleType_Sint,
        .u_int => wgpu.WGPUTextureSampleType_Uint,
    };
}

// TextureViewDimension
pub fn mapTextureViewDimension(view_dimension: TextureViewDimension) wgpu.WGPUTextureViewDimension {
    return switch (view_dimension) {
        .none => wgpu.WGPUTextureViewDimension_Undefined,
        .@"1d" => wgpu.WGPUTextureViewDimension_1D,
        .@"2d" => wgpu.WGPUTextureViewDimension_2D,
        .@"2d_array" => wgpu.WGPUTextureViewDimension_2DArray,
        .cube => wgpu.WGPUTextureViewDimension_Cube,
        .cube_array => wgpu.WGPUTextureViewDimension_CubeArray,
        .@"3d" => wgpu.WGPUTextureViewDimension_3D,
    };
}
// endregion

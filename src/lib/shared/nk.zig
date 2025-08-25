const std = @import("std");
const wgpu = @import("./wgpu.zig");
const core = @import("../core.zig");
const nk = @cImport({
    @cDefine("NK_INCLUDE_FIXED_TYPES", "1");
    @cDefine("NK_INCLUDE_DEFAULT_ALLOCATOR", "1");
    @cDefine("NK_INCLUDE_STANDARD_VARARGS", "1");
    @cDefine("NK_INCLUDE_FONT_BAKING", "1");
    @cDefine("NK_INCLUDE_DEFAULT_FONT", "1");
    @cDefine("NK_INCLUDE_VERTEX_BUFFER_OUTPUT", "1");
    @cInclude("nuklear.h");
});
pub usingnamespace nk;

pub const NkTex = struct {
    tex: wgpu.WGPUTexture,
    view: wgpu.WGPUTextureView,
    samp: wgpu.WGPUSampler,
};

pub const DrawCmd = struct {
    elem_count: u32,
    clip_x: i32,
    clip_y: i32,
    clip_w: u32,
    clip_h: u32,
    tex_handle: usize,
    index_offset: u32,
};

pub const DrawList = struct {
    vertices: []const u8,
    indices: []const u8,
    cmds: []DrawCmd,
    vertex_stride: u32 = 20,
    index_is_u16: bool = true,
};

const UiInput = struct {
    // mouse
    mouse_x: f32 = 0,
    mouse_y: f32 = 0,
    mouse_down: [3]bool = .{ false, false, false },
    mouse_pressed: [3]bool = .{ false, false, false },
    scroll_x: f32 = 0,
    scroll_y: f32 = 0,

    // text
    chars: std.ArrayList(u32),

    // keyboard
    keys_down: [512]bool = .{} ** 512,
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,

    pub fn resetPerFrame(self: *UiInput) void {
        self.scroll_x = 0;
        self.scroll_y = 0;
        self.mouse_pressed = .{ false, false, false };
        self.chars.clearRetainingCapacity();
    }
};

fn createNkFontTexture(device: *const core.Device, queue: *const core.Queue, pixels: [*]const u8, w: u32, h: u32) NkTex {
    const text_desc = wgpu.WGPUTextureDescriptor{
        .usage = wgpu.WGPUTextureUsage_TextureBinding | wgpu.WGPUTextureUsage_CopyDst,
        .dimension = wgpu.WGPUTextureDimension_2D,
        .size = .{ .width = w, .height = h, .depthOrArrayLayers = 1 },
        .format = wgpu.WGPUTextureFormat_RGBA8Unorm,
        .mipLevelCount = 1,
        .sampleCount = 1,
        .viewFormatCount = 0,
        .viewFormats = null,
        .label = wgpu.sliceToSv("nk_font"),
    };
    const tex = wgpu.wgpuDeviceCreateTexture(device._d, &text_desc);
    const view = wgpu.wgpuTextureCreateView(tex, &.{
        .label = wgpu.sliceToSv("nk_font_view"),
        .mipLevelCount = 1,
        .arrayLayerCount = 1,
    });
    const samp = wgpu.wgpuDeviceCreateSampler(device._d, &.{
        .label = wgpu.sliceToSv("nk_font_sampler"),
        .maxAnisotropy = 1,
        .addressModeU = wgpu.WGPUAddressMode_ClampToEdge,
        .addressModeV = wgpu.WGPUAddressMode_ClampToEdge,
        .addressModeW = wgpu.WGPUAddressMode_ClampToEdge,
        .magFilter = wgpu.WGPUFilterMode_Linear,
        .minFilter = wgpu.WGPUFilterMode_Linear,
    });

    const bytes_per_row: u32 = w * 4;
    var layout = wgpu.WGPUTexelCopyBufferLayout{
        .offset = 0,
        .bytesPerRow = bytes_per_row,
        .rowsPerImage = h,
    };
    var write = wgpu.WGPUTexelCopyTextureInfo{
        .texture = tex,
        .mipLevel = 0,
        .origin = .{ .x = 0, .y = 0, .z = 0 },
        .aspect = wgpu.WGPUTextureAspect_All,
    };
    var size = wgpu.WGPUExtent3D{
        .width = w,
        .height = h,
        .depthOrArrayLayers = 1,
    };
    wgpu.wgpuQueueWriteTexture(queue._q, &write, pixels, w * h * 4, &layout, &size);

    return NkTex{ .tex = tex, .view = view, .samp = samp };
}

pub const Nuklear = struct {
    ctx: nk.nk_context = undefined,
    atlas: nk.nk_font_atlas = undefined,

    font_image: ?[*]const u8 = null,
    font_w: nk.nk_int = 0,
    font_h: nk.nk_int = 0,
    null_tex: nk.nk_draw_null_texture = undefined,

    tex: NkTex,
    cmds: nk.nk_buffer = undefined,
    vbuf: nk.nk_buffer = undefined,
    ibuf: nk.nk_buffer = undefined,
    convert_config: nk.nk_convert_config = undefined,

    device: *const core.Device = undefined,
    queue: *const core.Queue = undefined,

    pub fn init(device: *const core.Device, queue: *const core.Queue) !Nuklear {
        var nuklear: Nuklear = undefined;
        try nuklear._init(device, queue);
        return nuklear;
    }

    fn _init(self: *Nuklear, device: *const core.Device, queue: *const core.Queue) !void {
        self.device = device;
        self.queue = queue;

        // Basic context with default alloc
        _ = nk.nk_init_default(&self.ctx, null);

        // Font atlas (CPU bake)
        nk.nk_font_atlas_init_default(&self.atlas);
        nk.nk_font_atlas_begin(&self.atlas);

        const font_cptr = nk.nk_font_atlas_add_default(&self.atlas, 13.0, null);
        if (font_cptr == null) return error.NoFont;

        const raw_img = nk.nk_font_atlas_bake(&self.atlas, &self.font_w, &self.font_h, nk.NK_FONT_ATLAS_RGBA32);
        self.font_image = if (raw_img) |p| @ptrCast(p) else null;

        self.tex = createNkFontTexture(device, queue, self.font_image.?, @intCast(self.font_w), @intCast(self.font_h));

        self.null_tex = .{
            .texture = nk.nk_handle_ptr(@ptrFromInt(@intFromPtr(self.tex.view))),
            .uv = nk.nk_vec2(0.5, 0.5),
        };
        nk.nk_font_atlas_end(&self.atlas, self.null_tex.texture, &self.null_tex);

        const font_ptr: *nk.nk_font = @ptrCast(font_cptr);
        nk.nk_style_set_font(&self.ctx, &font_ptr.*.handle);

        nk.nk_buffer_init_default(&self.cmds);
        nk.nk_buffer_init_default(&self.vbuf);
        nk.nk_buffer_init_default(&self.ibuf);

        var layout = [_]nk.nk_draw_vertex_layout_element{
            nk.nk_draw_vertex_layout_element{ .attribute = nk.NK_VERTEX_POSITION, .format = nk.NK_FORMAT_FLOAT, .offset = 0 },
            nk.nk_draw_vertex_layout_element{ .attribute = nk.NK_VERTEX_TEXCOORD, .format = nk.NK_FORMAT_FLOAT, .offset = 8 },
            nk.nk_draw_vertex_layout_element{ .attribute = nk.NK_VERTEX_COLOR, .format = nk.NK_FORMAT_R8G8B8A8, .offset = 16 },
            nk.nk_draw_vertex_layout_element{ .attribute = nk.NK_VERTEX_ATTRIBUTE_COUNT, .format = nk.NK_FORMAT_COUNT, .offset = 0 }, // sentinel
        };
        self.convert_config = nk.nk_convert_config{
            .vertex_layout = &layout,
            .vertex_size = 20,
            .vertex_alignment = 4,
            .tex_null = self.null_tex,
            .circle_segment_count = 22,
            .curve_segment_count = 22,
            .arc_segment_count = 22,
            .global_alpha = 1.0,
            .line_AA = nk.NK_ANTI_ALIASING_ON,
            .shape_AA = nk.NK_ANTI_ALIASING_ON,
        };
    }

    pub fn deinit(self: *Nuklear) void {
        nk.nk_font_atlas_clear(&self.atlas);
        nk.nk_free(&self.ctx);
    }

    pub fn newFrame(self: *Nuklear) void {
        nk.nk_input_begin(&self.ctx);
        nk.nk_input_end(&self.ctx);
    }

    pub fn build(self: *Nuklear, allocator: std.mem.Allocator) !DrawList {
        nk.nk_buffer_clear(&self.cmds);
        nk.nk_buffer_clear(&self.vbuf);
        nk.nk_buffer_clear(&self.ibuf);

        _ = nk.nk_convert(&self.ctx, &self.cmds, &self.vbuf, &self.ibuf, &self.convert_config);

        scaleNkVertices(&self.vbuf, 2);

        const vptr_any = nk.nk_buffer_memory_const(&self.vbuf).?;
        const iptr_any = nk.nk_buffer_memory_const(&self.ibuf).?;
        const vbytes: [*]const u8 = @ptrCast(vptr_any);
        const ibytes: [*]const u8 = @ptrCast(iptr_any);

        const vlen = nk.nk_buffer_total(&self.vbuf);
        const ilen = nk.nk_buffer_total(&self.ibuf);

        const draw_cmds = try self.buildDrawCmds(allocator);

        return DrawList{
            .vertices = vbytes[0..vlen],
            .indices = ibytes[0..ilen],
            .cmds = draw_cmds,
        };
    }

    fn scaleNkVertices(vbuf: *nk.nk_buffer, scale: f32) void {
        const NkVertex = extern struct {
            // offsets: pos=0, uv=8, col=16 — vertex_size = 20
            pos: [2]f32, // 8 bytes
            uv: [2]f32, // 8 bytes
            col: u32, // 4 bytes (RGBA8)
        };

        // Pointeur brut mutable vers le storage du buffer
        const raw_any: ?*anyopaque = nk.nk_buffer_memory(vbuf);
        if (raw_any == null) return;

        // Cast + align: tu avais .vertex_alignment = 4, donc aligne à 4.
        const raw_bytes: [*]u8 = @ptrCast(raw_any.?);
        const aligned: [*]align(4) u8 = @alignCast(raw_bytes);

        // Revue typée sur ce blob
        const total_bytes: usize = @intCast(nk.nk_buffer_total(vbuf));
        const vtx_count: usize = total_bytes / @sizeOf(NkVertex);

        var verts: [*]NkVertex = @ptrCast(aligned);

        var i: usize = 0;
        while (i < vtx_count) : (i += 1) {
            verts[i].pos[0] *= scale; // x
            verts[i].pos[1] *= scale; // y
            // uv / col inchangés
        }
    }

    fn buildDrawCmds(self: *Nuklear, allocator: std.mem.Allocator) ![]DrawCmd {
        var list = std.ArrayList(DrawCmd).init(allocator);
        var idx_offset: u32 = 0;

        var it: ?*const nk.nk_draw_command = nk.nk__draw_begin(&self.ctx, &self.cmds);
        while (it) |cmd| : (it = nk.nk__draw_next(@ptrCast(cmd), &self.cmds, &self.ctx)) {
            const elems: u32 = @intCast(cmd.elem_count);
            if (elems == 0) continue;

            const cr = cmd.clip_rect;
            const clip_x: i32 = @intFromFloat(cr.x);
            const clip_y: i32 = @intFromFloat(cr.y);
            const clip_w: u32 = @intFromFloat(@max(0.0, cr.w));
            const clip_h: u32 = @intFromFloat(@max(0.0, cr.h));

            try list.append(DrawCmd{
                .elem_count = elems,
                .clip_x = clip_x * 2,
                .clip_y = clip_y * 2,
                .clip_w = clip_w * 2,
                .clip_h = clip_h * 2,
                .tex_handle = @intFromPtr(cmd.texture.ptr),
                .index_offset = idx_offset,
            });

            idx_offset += elems;
        }

        return list.toOwnedSlice();
    }

    pub fn endFrame(self: *Nuklear) void {
        nk.nk_clear(&self.ctx);
    }

    pub fn demoWindow(self: *Nuklear) void {
        const bounds = nk.nk_rect(30, 30, 260, 140);
        const flags: nk.nk_flags = nk.NK_WINDOW_BORDER | nk.NK_WINDOW_MOVABLE | nk.NK_WINDOW_MINIMIZABLE | nk.NK_WINDOW_TITLE;
        if (nk.nk_begin(&self.ctx, "Nuklear Demo", bounds, flags) != 0) {
            nk.nk_layout_row_dynamic(&self.ctx, 30.0, 1);

            _ = nk.nk_button_label(&self.ctx, "Hello");
        }
        nk.nk_end(&self.ctx);
    }
};

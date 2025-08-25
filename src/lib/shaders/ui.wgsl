struct UBO {
  scale: vec2<f32>,
  translate: vec2<f32>,
};
@group(0) @binding(0) var samp0: sampler;
@group(0) @binding(1) var tex0: texture_2d<f32>;
@group(0) @binding(2) var<uniform> u: UBO;

struct VSIn {
  @location(0) pos: vec2<f32>,
  @location(1) uv: vec2<f32>,
  @location(2) col: vec4<f32>,
};
struct VSOut {
  @builtin(position) pos_cs: vec4<f32>,
  @location(0) uv: vec2<f32>,
  @location(1) col: vec4<f32>,
};

@vertex
fn vs_main(in: VSIn) -> VSOut {
  var out: VSOut;
  let p = in.pos * u.scale + u.translate;
  out.pos_cs = vec4<f32>(p, 0.0, 1.0);
  out.uv = in.uv;
  out.col = in.col;
  return out;
}

@fragment
fn fs_main(in: VSOut) -> @location(0) vec4<f32> {
  let texc = textureSample(tex0, samp0, in.uv);
  return in.col * texc;
}
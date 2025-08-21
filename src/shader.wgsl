struct CameraUBO { vp: mat4x4<f32> };

struct LightUBO {
  pos: vec3<f32>,
  _pad: f32,
  color: vec3<f32>,
  _pad2: f32,
};

struct ObjectUBO { model: mat4x4<f32> };

@group(0) @binding(0) var<uniform> gCamera: CameraUBO;
@group(0) @binding(1) var<uniform> gLight: LightUBO;

@group(1) @binding(0) var tex0: texture_2d<f32>;
@group(1) @binding(1) var samp0: sampler;

@group(2) @binding(0) var<uniform> gObj: ObjectUBO;

struct VSOut {
  @builtin(position) pos: vec4<f32>,
  @location(0) uv: vec2<f32>,
  @location(1) normal: vec3<f32>,
  @location(2) worldPos: vec3<f32>,
};

@vertex
fn vs_main(@location(0) in_pos: vec3<f32>, @location(1) in_uv: vec2<f32>, @location(2) in_normal: vec3<f32>) -> VSOut {
  var out: VSOut;
  let worldPos = gObj.model * vec4<f32>(in_pos, 1.0);
  
  out.pos = gCamera.vp * worldPos;
  out.uv = in_uv;
  out.normal = (gObj.model * vec4<f32>(in_normal, 0.0)).xyz;
  out.worldPos = worldPos.xyz;

  return out;
}

@fragment
fn fs_main(in: VSOut) -> @location(0) vec4<f32> {
  let N = normalize(in.normal);
  let L = normalize(gLight.pos - in.worldPos);
  let lambert = max(dot(N, L), 0.0);

  let baseColor = textureSample(tex0, samp0, in.uv);
  return vec4<f32>(baseColor.rgb * gLight.color * lambert, baseColor.a);
}
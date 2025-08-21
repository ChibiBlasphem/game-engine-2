struct FrameUBO {
  vp      : mat4x4<f32>,
  inv_vp  : mat4x4<f32>,   // ← nécessaire pour remonter en monde
  cam_pos : vec3<f32>,
  _pad    : f32,
};
@group(0) @binding(0) var<uniform> gFrame: FrameUBO;

struct VSOut {
  @builtin(position) pos_cs : vec4<f32>,
  @location(0) ndc          : vec2<f32>, // passé au FS
};

@vertex
fn vs_main(@builtin(vertex_index) vid: u32) -> VSOut {
  // Quad énorme sur Y=0, centré sur cam (XZ)
  let R: f32 = 10000.0;
  var p = array<vec2<f32>,4>(
    vec2<f32>(-R, -R),
    vec2<f32>( R, -R),
    vec2<f32>(-R,  R),
    vec2<f32>( R,  R),
  );

  var out: VSOut;
  out.ndc = p[vid];                         // NDC xy
  out.pos_cs = vec4<f32>(p[vid], 0.0, 1.0); // position clip
  return out;
}

// ==== Utils ========================================================
fn pixel_size_world(world_pos: vec3<f32>) -> f32 {
  let px_x = length(vec2<f32>(dpdx(world_pos.x), dpdy(world_pos.x)));
  let px_z = length(vec2<f32>(dpdx(world_pos.z), dpdy(world_pos.z)));
  return max(px_x, px_z);
}
fn edge_aa(half_w: f32, px_ws: f32) -> f32 {
  let aa_min = 0.0005;
  let aa_max = half_w * 0.40;
  return clamp(px_ws, aa_min, aa_max);
}
fn dist_to_grid(p: f32, s: f32) -> f32 {
  let f = fract(p / s);
  return min(f, 1.0 - f) * s;
}
fn line_mask(d: f32, half_w: f32, px_ws: f32) -> f32 {
  let aa = edge_aa(half_w, px_ws);
  return 1.0 - smoothstep(half_w - aa, half_w + aa, d);
}
fn ray_world(ndc: vec2<f32>) -> vec3<f32> {
  let p_clip  = vec4<f32>(ndc, 1.0, 1.0);
  let p_world = gFrame.inv_vp * p_clip;
  return (p_world.xyz / p_world.w);
}

// ==== Fragment =====================================================
@fragment
fn fs_main(@location(0) ndc: vec2<f32>) -> @location(0) vec4<f32> {
  let ro = gFrame.cam_pos;
  let pw = ray_world(ndc);
  let rd = normalize(pw - ro);

  let eps = 1e-6;
  if (abs(rd.y) < eps) { return vec4<f32>(0.0, 0.0, 0.0, 0.0); }
  let t = -ro.y / rd.y;
  if (t <= 0.0) { return vec4<f32>(0.0, 0.0, 0.0, 0.0); }

  let t_max : f32 = 5000.0;
  if (t > t_max) { return vec4<f32>(0.0, 0.0, 0.0, 0.0); }

  let world_pos = ro + rd * t;
  let view_dir  = normalize(ro - world_pos); // (garde si tu veux du tint mineur)

  // Couleurs
  let col_minor   = vec3<f32>(0.60, 0.62, 0.65);
  let col_major   = vec3<f32>(0.52, 0.54, 0.58);
  let col_axis_x  = vec3<f32>(1.00, 0.25, 0.25); // ROUGE PLEIN
  let col_axis_z  = vec3<f32>(0.25, 0.50, 1.00); // BLEU  PLEIN

  // Paramètres
  let spacing_major : f32 = 1.0;
  let subdiv        : f32 = 10.0;
  let spacing_minor : f32 = spacing_major / subdiv;

  let w_minor : f32 = 0.001;
  let w_major : f32 = 0.002;
  let w_axis  : f32 = w_major;   // mêmes épaisseurs que majeures

  let a_minor : f32 = 0.28;
  let a_major : f32 = 0.50;
  let a_axis  : f32 = 0.50;

  let px_ws = pixel_size_world(world_pos);

  // distances
  let d_minor_x = dist_to_grid(world_pos.z, spacing_minor);
  let d_minor_z = dist_to_grid(world_pos.x, spacing_minor);
  let d_major_x = dist_to_grid(world_pos.z, spacing_major);
  let d_major_z = dist_to_grid(world_pos.x, spacing_major);
  let d_axis_x  = abs(world_pos.z);
  let d_axis_z  = abs(world_pos.x);

  // masques
  let m_minor_x = line_mask(d_minor_x, w_minor, px_ws);
  let m_minor_z = line_mask(d_minor_z, w_minor, px_ws);
  let m_major_x = line_mask(d_major_x, w_major, px_ws);
  let m_major_z = line_mask(d_major_z, w_major, px_ws);
  let m_axis_x  = line_mask(d_axis_x,  w_axis,  px_ws);
  let m_axis_z  = line_mask(d_axis_z,  w_axis,  px_ws);

  // (optionnel) léger tint directionnel sur les mineures/majeures
  let f_x = pow(max(0.0, abs(dot(view_dir, vec3<f32>(1.0, 0.0, 0.0)))), 0.75);
  let f_z = pow(max(0.0, abs(dot(view_dir, vec3<f32>(0.0, 0.0, 1.0)))), 0.75);
  let tint_minor : f32 = 0.10;
  let tint_major : f32 = 0.20;

  // --- Composition (fond transparent) ---
  var out_col = vec3<f32>(0.0);
  var out_a   = 0.0;

  // Mineures
  let sx = m_minor_x * a_minor;
  if (sx > out_a) { out_col = mix(col_minor, col_axis_x, tint_minor * f_x); out_a = sx; }
  let sz = m_minor_z * a_minor;
  if (sz > out_a) { out_col = mix(col_minor, col_axis_z, tint_minor * f_z); out_a = sz; }

  // Majeures
  let mx = m_major_x * a_major;
  if (mx > out_a) { out_col = mix(col_major, col_axis_x, tint_major * f_x); out_a = mx; }
  let mz = m_major_z * a_major;
  if (mz > out_a) { out_col = mix(col_major, col_axis_z, tint_major * f_z); out_a = mz; }

  // AXES EN DERNIER → ROUGE/ BLEU PUR (pas teinté), même épaisseur/alpha que majeures
  let ax = m_axis_x * a_axis;
  if (ax > 0.0) { out_col = col_axis_x; out_a = max(out_a, ax); }
  let az = m_axis_z * a_axis;
  if (az > 0.0) { out_col = col_axis_z; out_a = max(out_a, az); }

  if (out_a <= 0.0) { return vec4<f32>(0.0, 0.0, 0.0, 0.0); }

  // petit fade distance optionnel
  let fade_dist : f32 = 4000.0;
  let d = length(world_pos.xz - gFrame.cam_pos.xz);
  let fade = clamp(1.0 - d / fade_dist, 0.0, 1.0);
  out_a *= fade;

  return vec4<f32>(out_col, out_a);
}
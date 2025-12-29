// ============================================================================
// ClosestHit.hlsl - Closest Hit Shader 模块
// ============================================================================

#include "common.hlsl"
#include "direct_lighting.hlsl"

[shader("closesthit")] void ClosestHitMain(inout RayPayload payload, in BuiltInTriangleIntersectionAttributes attr) {
  payload.hit = true;
  
  // Get material index from instance
  uint material_idx = InstanceID();
  payload.instance_id = material_idx;
  
  // Load material
  Material mat = materials[material_idx];
  
  // Get vertex from geometry
  uint primitiveID = PrimitiveIndex();
  int index0 = Indices[material_idx][primitiveID * 3 + 0];
  int index1 = Indices[material_idx][primitiveID * 3 + 1];
  int index2 = Indices[material_idx][primitiveID * 3 + 2];

  Vertex v0 = Vertices[material_idx][index0];
  Vertex v1 = Vertices[material_idx][index1];
  Vertex v2 = Vertices[material_idx][index2];

  // Use uv to get texcoords
  float2 uv0 = Texcoords[material_idx][index0];
  float2 uv1 = Texcoords[material_idx][index1];
  float2 uv2 = Texcoords[material_idx][index2];

  float2 bc = attr.barycentrics;
  float3 bary = float3(1.0 - bc.x - bc.y, bc.x, bc.y);
  float2 uv = uv0 * bary.x + uv1 * bary.y + uv2 * bary.z;
  
  // ============================================================================
  // Handle missing UV coordinates: Generate UV from vertex positions if UV is invalid
  // ============================================================================
  // Check if UV is valid (not all zeros, which indicates missing UV data)
  float uv_valid = (length(uv0) > 0.001 || length(uv1) > 0.001 || length(uv2) > 0.001) ? 1.0 : 0.0;
  
  if (uv_valid < 0.5) {
    // Generate UV from vertex positions (simple box mapping)
    // Use object space positions from vertices
    float3 pos0 = v0.position;
    float3 pos1 = v1.position;
    float3 pos2 = v2.position;
    float3 interp_pos = pos0 * bary.x + pos1 * bary.y + pos2 * bary.z;
    
    // Simple box mapping: project onto dominant axis
    float3 abs_pos = abs(interp_pos);
    float max_axis = max(abs_pos.x, max(abs_pos.y, abs_pos.z));
    
    if (abs_pos.x == max_axis) {
      // Project onto YZ plane
      uv = float2(interp_pos.z, interp_pos.y) * 0.5 + 0.5;
    } else if (abs_pos.y == max_axis) {
      // Project onto XZ plane
      uv = float2(interp_pos.x, interp_pos.z) * 0.5 + 0.5;
    } else {
      // Project onto XY plane
      uv = float2(interp_pos.x, interp_pos.y) * 0.5 + 0.5;
    }
  }

  float3 base_color_tex = (mat.base_color_tex >= 0) ? Textures[mat.base_color_tex].SampleLevel(LinearWrap, uv, 0.0f).rgb : float3(1.0f, 1.0f, 1.0f);
  float alpha_tex = (mat.base_color_tex >= 0) ? Textures[mat.base_color_tex].SampleLevel(LinearWrap, uv, 0.0f).a : 1.0f;
  float metallic_roughness_tex = (mat.metallic_roughness_tex >= 0) ? Textures[mat.metallic_roughness_tex].SampleLevel(LinearWrap, uv, 0.0f).b : 1.0f;
  float roughness_tex = (mat.metallic_roughness_tex >= 0) ? Textures[mat.metallic_roughness_tex].SampleLevel(LinearWrap, uv, 0.0f).g : 1.0f;
  float3 emissive_tex = (mat.emissive_texture >= 0) ? Textures[mat.emissive_texture].SampleLevel(LinearWrap, uv, 0.0f).rgb : float3(1.0f, 1.0f, 1.0f);
  float AO_tex = (mat.AO_texture >= 0) ? Textures[mat.AO_texture].SampleLevel(LinearWrap, uv, 0.0f).r : 1.0f;

  float3 base_color = mat.base_color_factor.rgb * base_color_tex;
  float alpha = mat.base_color_factor.a * alpha_tex;
  float metallic = mat.metallic_factor * metallic_roughness_tex;
  float roughness = max(0.1f, mat.roughness_factor * roughness_tex);
  float3 emission = mat.emissive_factor * emissive_tex;
  float AO = 1.0 + (AO_tex - 1.0) * mat.AO_strength;

  // ============================================================================
  // Multi-Layer Material: Sample Layer 2 (Outer Layer) Textures
  // ============================================================================
  
  float3 base_color_tex_layer2 = (mat.base_color_tex_layer2 >= 0) ? Textures[mat.base_color_tex_layer2].SampleLevel(LinearWrap, uv, 0.0f).rgb : float3(1.0f, 1.0f, 1.0f);
  float alpha_tex_layer2 = (mat.base_color_tex_layer2 >= 0) ? Textures[mat.base_color_tex_layer2].SampleLevel(LinearWrap, uv, 0.0f).a : 1.0f;
  float metallic_roughness_tex_layer2 = (mat.metallic_roughness_tex_layer2 >= 0) ? Textures[mat.metallic_roughness_tex_layer2].SampleLevel(LinearWrap, uv, 0.0f).b : 1.0f;
  float roughness_tex_layer2 = (mat.metallic_roughness_tex_layer2 >= 0) ? Textures[mat.metallic_roughness_tex_layer2].SampleLevel(LinearWrap, uv, 0.0f).g : 1.0f;
  float3 emissive_tex_layer2 = (mat.emissive_texture_layer2 >= 0) ? Textures[mat.emissive_texture_layer2].SampleLevel(LinearWrap, uv, 0.0f).rgb : float3(1.0f, 1.0f, 1.0f);
  float AO_tex_layer2 = (mat.AO_texture_layer2 >= 0) ? Textures[mat.AO_texture_layer2].SampleLevel(LinearWrap, uv, 0.0f).r : 1.0f;

  // Compute Layer 2 material properties
  float3 base_color_layer2 = mat.base_color_factor_layer2.rgb * base_color_tex_layer2;
  float alpha_layer2 = mat.base_color_factor_layer2.a * alpha_tex_layer2;
  float metallic_layer2 = mat.metallic_factor_layer2 * metallic_roughness_tex_layer2;
  float roughness_layer2 = max(0.1f, mat.roughness_factor_layer2 * roughness_tex_layer2);
  float3 emission_layer2 = mat.emissive_factor_layer2 * emissive_tex_layer2;
  float AO_layer2 = 1.0 + (AO_tex_layer2 - 1.0) * mat.AO_strength_layer2;

  // Compute normal
  float3 n0 = Normals[material_idx][index0];
  float3 n1 = Normals[material_idx][index1];
  float3 n2 = Normals[material_idx][index2];

  float3 normal = float3(0.0, 0.0, 0.0);
  if (length(n0) < 0.001 || length(n1) < 0.001 || length(n2) < 0.001) {
    // use geometric normal
    float3 edge1 = v1.position - v0.position;
    float3 edge2 = v2.position - v0.position;
    normal = normalize(cross(edge1, edge2));
  } else {
    // use interpolated normal
    float2 bc = attr.barycentrics;
    float3 bary = float3(1.0 - bc.x - bc.y, bc.x, bc.y);
    normal = n0 * bary.x + n1 * bary.y + n2 * bary.z;
    normal = normalize(normal);
  }

  float3 world_normal = normalize(mul(ObjectToWorld3x4(), float4(normal, 0.0)));
  float3 geometric_normal = world_normal;

  payload.front_face = true;
  if (dot(world_normal, WorldRayDirection()) > 0.0) {
    world_normal = -world_normal;
    geometric_normal = -geometric_normal;
    payload.front_face = false;
  }

  if (mat.normal_texture >= 0) {
    float3 tangent = normalize(Tangents[material_idx][index0] * bary.x +
                     Tangents[material_idx][index1] * bary.y +
                     Tangents[material_idx][index2] * bary.z);

    float3 world_tangent = normalize(mul((float3x3)ObjectToWorld3x4(), tangent));

    world_tangent = normalize(world_tangent - dot(world_tangent, world_normal) * world_normal);

    float3 world_bitangent = normalize(cross(world_normal, world_tangent));

    float3 normal_map_sample = Textures[mat.normal_texture].SampleLevel(LinearWrap, uv, 0.0f).rgb;
    normal_map_sample = normal_map_sample * 2.0 - 1.0;
    normal_map_sample.xy *= mat.normal_scale;

    // Transform normal from tangent space to world space
    world_normal = normalize(normal_map_sample.x * world_tangent + normal_map_sample.y * world_bitangent + normal_map_sample.z * world_normal);
  }

  payload.position = WorldRayOrigin() + WorldRayDirection() * RayTCurrent();
  payload.normal = world_normal;
  payload.geometric_normal = geometric_normal;

  payload.albedo = base_color;

  payload.roughness = roughness;
  payload.metallic = metallic;

  payload.emission = emission;

  payload.ao = AO;

  payload.clearcoat = mat.clearcoat_factor;
  payload.clearcoat_roughness = mat.clearcoat_roughness_factor;

  payload.transmission = mat.transmission;
  payload.ior = mat.ior;
  payload.dispersion = mat.dispersion;
  payload.new_eps = RayTCurrent() * 1e-4 + eps;
  
  payload.alpha_mode = mat.alpha_mode;
  payload.alpha = alpha;
  
  // ============================================================================
  // Multi-Layer Material: Store Layer 2 Properties in RayPayload
  // ============================================================================
  
  payload.albedo_layer2 = base_color_layer2;
  payload.roughness_layer2 = roughness_layer2;
  payload.metallic_layer2 = metallic_layer2;
  payload.emission_layer2 = emission_layer2;
  payload.ao_layer2 = AO_layer2;
  payload.clearcoat_layer2 = mat.clearcoat_factor_layer2;
  payload.clearcoat_roughness_layer2 = mat.clearcoat_roughness_factor_layer2;
  payload.transmission_layer2 = mat.transmission_layer2;
  payload.ior_layer2 = mat.ior_layer2;
  payload.dispersion_layer2 = mat.dispersion_layer2;
  payload.alpha_mode_layer2 = mat.alpha_mode_layer2;
  payload.alpha_layer2 = alpha_layer2;
  
  // Multi-Layer Material Control Parameters
  payload.thin = mat.thin;
  payload.blend_factor = mat.blend_factor;
  payload.layer_thickness = mat.layer_thickness;
  
  // Calculate direct lighting
  payload.direct_light = float3(0.0, 0.0, 0.0);
  float3 view_dir = -normalize(WorldRayDirection());
  
  // Sample all lights
  // Check if multi-layer material (blend_factor > 0 means multi-layer is active)
  if (payload.blend_factor > 0.0) {
    // Use multi-layer material BRDF
    for (uint i = 0; i < hover_info.light_count; ++i) {
      Light light = Lights[i];
      payload.direct_light += EvaluateLightMultiLayer(
        light, payload.position, payload.normal, payload.geometric_normal, view_dir,
        payload.albedo, payload.roughness, payload.metallic,
        payload.ao, payload.clearcoat, payload.clearcoat_roughness,
        payload.albedo_layer2, payload.roughness_layer2, payload.metallic_layer2,
        payload.ao_layer2, payload.clearcoat_layer2, payload.clearcoat_roughness_layer2,
        payload.thin, payload.blend_factor, payload.layer_thickness,
        payload.alpha_layer2,  // Pass alpha for transparency support
        payload.rng_state
      );
    }
  } else {
    // Use single-layer material BRDF (backward compatible)
    for (uint i = 0; i < hover_info.light_count; ++i) {
      Light light = Lights[i];
      payload.direct_light += EvaluateLight(
        light, payload.position, payload.normal, payload.geometric_normal, view_dir,
        payload.albedo, payload.roughness, payload.metallic,
        payload.ao, payload.clearcoat, payload.clearcoat_roughness,
        payload.rng_state
      );
    
  }
}
}


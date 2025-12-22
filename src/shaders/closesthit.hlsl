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

  payload.front_face = true;
  if (dot(world_normal, WorldRayDirection()) > 0.0) {
    world_normal = -world_normal;
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
  
  // Calculate direct lighting
  payload.direct_light = float3(0.0, 0.0, 0.0);
  float3 view_dir = -normalize(WorldRayDirection());
  
  // Sample all lights
  for (uint i = 0; i < hover_info.light_count; ++i) {
    Light light = Lights[i];
    payload.direct_light += EvaluateLight(light, payload.position, payload.normal, view_dir, payload.albedo, payload.roughness, payload.metallic, payload.ao, payload.clearcoat, payload.clearcoat_roughness, payload.rng_state);
  }
}


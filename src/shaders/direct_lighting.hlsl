// ============================================================================
// Direct_Lighting.hlsl - 直接光照计算模块
// ============================================================================

#ifndef DIRECT_LIGHTING_HLSL
#define DIRECT_LIGHTING_HLSL

#include "common.hlsl"
#include "light_sampling.hlsl"
#include "shadow.hlsl"
#include "brdf.hlsl"

float3 EvaluateLight(Light light, float3 position, float3 normal, float3 view_dir, float3 albedo, float roughness, float metallic, float ao, float clearcoat, float clearcoat_roughness, inout uint rng_state) {
  float3 direct_light = float3(0.0, 0.0, 0.0);
  
  // POINT_LIGHT
  float3 light_dir;
  float3 radiance;
  float inv_pdf;
  float max_distance;
  if (light.type == 0) {
    radiance = SamplePointLight(light, position, light_dir, inv_pdf);
    max_distance = length(light.position - position);
  } else if (light.type == 1) {
    float3 sampled_point;
    radiance = SampleAreaLight(light, position, light_dir, inv_pdf, sampled_point, rng_state);
    max_distance = length(sampled_point - position);
  }
  float NdotL = max(dot(normal, light_dir), 0.0);
  if (NdotL > 0.0) {
    // [Fix] Clamp roughness for NEE to reduce fireflies on smooth surfaces
    float safe_roughness = max(roughness, 0.15);
    float3 brdf = eval_brdf(normal, light_dir, view_dir, albedo, safe_roughness, metallic, ao, clearcoat, clearcoat_roughness);
    if (!CastShadowRay(position + normal * 1e-3, light_dir, max_distance - 1e-3)) {
      direct_light = brdf * radiance * NdotL * inv_pdf;
    }
  }
  return direct_light;
}

#endif // DIRECT_LIGHTING_HLSL


// ============================================================================
// Light_Sampling.hlsl - 光源采样模块
// ============================================================================

#ifndef LIGHT_SAMPLING_HLSL
#define LIGHT_SAMPLING_HLSL

#include "common.hlsl"
#include "rng.hlsl"

// Light sampling functions
float3 SamplePointLight(Light light, float3 position, out float3 light_dir, inout float inv_pdf) {
  light_dir = normalize(light.position - position);
  inv_pdf = 1.0f;
  float dist_sq = dot(light.position - position, light.position - position);
  return light.color * light.intensity / dist_sq;
}

float3 SampleAreaLight(Light light, float3 position, out float3 light_dir, inout float inv_pdf, inout float3 sampled_point, inout uint rng_state) {
	// Sample a point on the area light
  float u1 = rand(rng_state);
	float u2 = rand(rng_state);

	sampled_point = light.position + (u1 - 0.5f) * light.u + (u2 - 0.5f) * light.v;
	light_dir = normalize(sampled_point - position);

	float area = length(cross(light.u, light.v));
	float dist_sq = dot(sampled_point - position, sampled_point - position);
	float cos_theta = max(dot(-light_dir, normalize(light.direction)), 0.0f);

	// [Fix] Increase epsilon to prevent singularity/noise when close to light
	inv_pdf = area * cos_theta / max(dist_sq, 1e-2);

	return light.color * light.intensity;
}

#endif // LIGHT_SAMPLING_HLSL


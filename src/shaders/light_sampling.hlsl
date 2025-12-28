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

	// ========================================================================
	// Firefly Reduction: Improved PDF Calculation (Scheme 2)
	// ========================================================================
	// Clamp extreme values to prevent fireflies
	dist_sq = max(dist_sq, 0.01); // Minimum distance 0.1
	cos_theta = max(cos_theta, 0.01); // Minimum angle ~84 degrees
	
	// Calculate inv_pdf and clamp to reasonable range
	inv_pdf = area * cos_theta / dist_sq;
	inv_pdf = clamp(inv_pdf, 1e-3, 1e3); // Limit to reasonable range

	return light.color * light.intensity;
}

// Directional (sun) light: uniform sampling over a cone with half-angle = angular_radius
float3 SampleSunLight(Light light, out float3 light_dir, out float inv_pdf, inout uint rng_state) {
	// Build an orthonormal basis around the mean sun direction
	float3 w = normalize(-light.direction);
	float3 up = (abs(w.z) < 0.999f) ? float3(0.0f, 0.0f, 1.0f) : float3(1.0f, 0.0f, 0.0f);
	float3 u = normalize(cross(up, w));
	float3 v = cross(w, u);

	float theta = max(light.angular_radius, 1e-4); // avoid zero solid angle
	float cosThetaMax = cos(theta);

	float u1 = rand(rng_state);
	float u2 = rand(rng_state);
	float cosTheta = lerp(cosThetaMax, 1.0f, u1);
	float sinTheta = sqrt(max(0.0f, 1.0f - cosTheta * cosTheta));
	float phi = 2.0f * PI * u2;

	light_dir = normalize(
		u * (sinTheta * cos(phi)) +
		v * (sinTheta * sin(phi)) +
		w * cosTheta);

	float solid_angle = max(2.0f * PI * (1.0f - cosThetaMax), 1e-6f);
	inv_pdf = solid_angle; // pdf = 1 / solid_angle
	return light.color * light.intensity; // Radiance, no distance falloff
}

#endif // LIGHT_SAMPLING_HLSL


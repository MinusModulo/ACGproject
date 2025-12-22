// ============================================================================
// Sampling.hlsl - 重要性采样模块
// ============================================================================

#ifndef SAMPLING_HLSL
#define SAMPLING_HLSL

#include "common.hlsl"
#include "brdf.hlsl"

// sample a cosine-weighted hemisphere direction
float3 sample_cosine_hemisphere(float u1, float u2) {
  float r = sqrt(u1);
  float phi = 2.0 * PI * u2;
  float x = r * cos(phi);
  float y = r * sin(phi);
  float z = sqrt(max(0.0, 1.0 - u1));
  return float3(x, y, z);
}

// sample GGX microfacet half-vector in tangent space
float3 sample_GGX_half(float u1, float u2, float roughness) {
  // using common mapping: sample theta via tan^2(theta) = a^2 * u1/(1-u1)
  float a = roughness * roughness;
  float tan2 = a * a * (u1 / max(eps, 1.0 - u1));
  float cosTheta = 1.0 / sqrt(1.0 + tan2);
  float sinTheta = sqrt(max(0.0, 1.0 - cosTheta * cosTheta));
  float phi = 2.0 * PI * u2;
  return float3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta);
}

float pdf_GGX_for_direction(float3 N, float3 V, float3 L, float roughness) {
  // returns p_spec(omega = L) = D(h) * cos_theta_h / (4 * V·H)
  float3 H = normalize(V + L);
  float NdotH = max(dot(N, H), 0.0);
  float VdotH = max(dot(V, H), 0.0);
  float D = D_GGX(NdotH, roughness);
  return (D * NdotH) / max(4.0 * VdotH, eps);
}

#endif // SAMPLING_HLSL


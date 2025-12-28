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

// sample uniform sphere direction
float3 sample_uniform_sphere(float u1, float u2) {
  float z = 1.0 - 2.0 * u1;
  float r = sqrt(max(0.0, 1.0 - z * z));
  float phi = 2.0 * PI * u2;
  return float3(r * cos(phi), r * sin(phi), z);
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

// ============================================================================
// PDF calculation for BRDF sampling strategy
// ============================================================================

// Calculate PDF for a direction under BRDF sampling strategy
// This combines diffuse and specular PDFs based on material properties
float pdf_brdf_for_direction(
    float3 N, float3 V, float3 L,
    float roughness, float metallic, float clearcoat, float clearcoat_roughness
) {
    float NdotL = max(dot(N, L), 0.0);
    if (NdotL <= 0.0) return 0.0;
    
    // Calculate Fresnel to determine specular vs diffuse probability
    float3 F0 = lerp(float3(0.04, 0.04, 0.04), float3(1.0, 1.0, 1.0), metallic);
    float3 F = F_Schlick(F0, max(dot(N, V), 0.0));
    float luminance = dot(F, float3(0.2126, 0.7152, 0.0722));
    
    // Base layer probabilities
    float q_spec_base = clamp(saturate(luminance), 0.05, 0.95);
    float q_diff_base = 1.0 - q_spec_base;
    
    // Clearcoat probability
    float p_clearcoat = 0.0;
    if (clearcoat > 0.0) {
        float F_cc = F_Schlick(float3(0.04, 0.04, 0.04), max(dot(N, V), 0.0)).r;
        p_clearcoat = clamp(clearcoat * 0.5, 0.0, 0.5);
    }
    float p_base = 1.0 - p_clearcoat;
    
    // Calculate PDFs for each strategy
    float pdf_diff = NdotL / PI;
    float pdf_spec_base = pdf_GGX_for_direction(N, V, L, roughness);
    float pdf_spec_cc = 0.0;
    if (clearcoat > 0.0) {
        pdf_spec_cc = pdf_GGX_for_direction(N, V, L, clearcoat_roughness);
    }
    
    // Combined PDF
    return p_clearcoat * pdf_spec_cc + p_base * (q_spec_base * pdf_spec_base + q_diff_base * pdf_diff);
}

// ============================================================================
// PDF calculation for light sampling strategy
// ============================================================================

// Calculate PDF for a direction under light sampling strategy
float pdf_light_for_direction(
    Light light, float3 position, float3 light_dir
) {
    if (light.type == 0) {
        // Point light: delta distribution, PDF is infinite (handled separately)
        return 1.0; // For point lights, we use inv_pdf = 1.0, so pdf = 1.0
    } else if (light.type == 2) {
      // Directional (sun) light: delta distribution
      return 1.0;
    } else if (light.type == 1) {
        // Area light: uniform sampling on light surface
        float area = length(cross(light.u, light.v));
        float dist_sq = dot(light.position - position, light.position - position);
        float cos_theta = max(dot(-light_dir, normalize(light.direction)), 0.0);
        return max(dist_sq, 1e-2) / (area * cos_theta);
    }
    return 0.0;
}

#endif // SAMPLING_HLSL


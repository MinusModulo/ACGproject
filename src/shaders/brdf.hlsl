// ============================================================================
// BRDF.hlsl - BRDF 计算模块
// ============================================================================

#ifndef BRDF_HLSL
#define BRDF_HLSL

#include "common.hlsl"

float3 F_Schlick(float3 f0, float u) {
  // F = F0 + (1 - F0) * (1 - cos)^5
  return f0 + (1.0 - f0) * pow(1.0 - u, 5.0);
}

float D_GGX(float NdotH, float roughness) {
  // D = a^2 / (pi * ((NdotH^2 * (a^2 - 1) + 1)^2))
  float a = roughness * roughness;
  float a2 = a * a;
  float NdotH2 = NdotH * NdotH;
  float denom = (NdotH2 * (a2 - 1.0) + 1.0);
  return a2 / max(PI * denom * denom, eps);
}

float G_Smith(float NdotV, float NdotL, float roughness) {
  // G = G1(in) * G1(out), G11 = 2 * (n * v) / (n * v  + sqrt(a2 + (1 - a2) * (n * v)^2))
  float a = roughness * roughness;
  float a2 = a * a;
  float ggx1 = 2 * NdotV / max(NdotV + sqrt(a2 + (1.0 - a2) * NdotV * NdotV), eps);
  float ggx2 = 2 * NdotL / max(NdotL + sqrt(a2 + (1.0 - a2) * NdotL * NdotL), eps);
  return ggx1 * ggx2;
}

float3 eval_brdf(float3 N, float3 L, float3 V, float3 albedo, float roughness, float metallic, float ao = 1.0, float clearcoat = 0.0, float clearcoat_roughness = 0.0) {
    float3 H = normalize(V + L);
    float NdotL = max(dot(N, L), 0.0);
    float NdotV = max(dot(N, V), 0.0);
    float NdotH = max(dot(N, H), 0.0);
    float VdotH = max(dot(V, H), 0.0);

    if (NdotL <= 0.0 || NdotV <= 0.0) return float3(0, 0, 0);

    float3 F0 = lerp(float3(0.04, 0.04, 0.04), albedo, metallic);
    float3 F = max(0.0f, F_Schlick(F0, VdotH));
    float D = max(0.0f, D_GGX(NdotH, roughness));
    float G = max(0.0f, G_Smith(NdotV, NdotL, roughness));

    float3 specular = (D * G * F) / max(4.0 * NdotV * NdotL, eps);
    
    float3 kS = F;
    float3 kD = (1.0 - kS) * (1.0 - metallic);
    float3 diffuse = kD * albedo / PI * ao;

    float3 base_layer = diffuse + specular;

    if (clearcoat > 0.0) {
        float Fc = F_Schlick(float3(0.04, 0.04, 0.04), VdotH).r;
        float Dc = D_GGX(NdotH, clearcoat_roughness);
        float Gc = G_Smith(NdotV, NdotL, clearcoat_roughness);

        float3 f_clearcoat = float3(Dc * Gc * Fc, Dc * Gc * Fc, Dc * Gc * Fc) / max(4.0 * NdotV * NdotL, eps);

        return f_clearcoat * clearcoat + (1.0 - Fc * clearcoat) * base_layer;
    }

    return base_layer;
}

#endif // BRDF_HLSL


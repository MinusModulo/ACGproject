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

// ============================================================================
// Cartoon Style Processing Functions
// ============================================================================

// Apply binary lighting or quantization to diffuse component for toon shading
float3 apply_cartoon_diffuse(float3 diffuse, float bands) {
    // Calculate luminance to preserve color relationships
    float luminance = dot(diffuse, float3(0.2126, 0.7152, 0.0722));
    
    // Binary lighting: completely flat (bright/dark two levels)
    // Use step function for hard threshold - no gradient
    float binary_threshold = render_settings.binary_threshold;
    float binary_value = step(binary_threshold, luminance);
    
    // Preserve color ratios while applying binary lighting
    // Scale the original color to match the binary luminance
    float3 binary_diffuse = diffuse;
    if (luminance > eps) {
        // Binary value is either 0.0 or 1.0
        // For bright areas (binary_value = 1.0), use full brightness
        // For dark areas (binary_value = 0.0), use a minimum brightness to prevent complete blackness
        float target_luminance = binary_value > 0.5 ? 1.0 : max(luminance * 0.3, 0.1);
        float scale = target_luminance / luminance;
        binary_diffuse = diffuse * scale;
    } else {
        // Very dark areas: keep original but ensure minimum visibility
        binary_diffuse = diffuse * 0.1;
    }
    
    // If bands is set to 2 or less, use binary mode
    // Otherwise, fall back to quantization for backward compatibility
    if (bands <= 2.0) {
        return binary_diffuse;
    }
    
    // Original quantization logic for bands > 2
    float quantized_luminance = round(luminance * bands) / bands;
    
    // Prevent darkening
    float min_luminance = luminance * 0.7;
    quantized_luminance = max(quantized_luminance, min_luminance);
    
    float3 quantized = diffuse;
    if (luminance > eps) {
        float scale = quantized_luminance / luminance;
        quantized = diffuse * scale;
    }
    
    // Enhance saturation
    float max_channel = max(max(quantized.r, quantized.g), quantized.b);
    float min_channel = min(min(quantized.r, quantized.g), quantized.b);
    float saturation = (max_channel > eps) ? (max_channel - min_channel) / max_channel : 0.0;
    
    float saturation_boost = 2.5;
    float new_saturation = min(saturation * saturation_boost, 1.0);
    
    if (max_channel > eps && saturation > 0.01) {
        float3 gray = float3(quantized_luminance, quantized_luminance, quantized_luminance);
        quantized = lerp(gray, quantized, new_saturation / max(saturation, 0.01));
    }
    
    if (saturation > 0.05) {
        float color_boost = 1.6;
        quantized = lerp(quantized, quantized * color_boost, saturation * 0.8);
    }
    
    return quantized;
}

// Apply flat sticker-like highlight to specular component for cartoon style
float3 apply_cartoon_specular(float3 specular, float hardness) {
    if (hardness <= 0.0) return specular;

    float luminance = dot(specular, float3(0.2126, 0.7152, 0.0722));
    
    // Flat highlight mode: completely flat, no gradient (sticker-like effect)
    // Use step function for hard threshold - creates completely flat highlight
    float highlight_threshold = render_settings.highlight_threshold;
    float flat_mask = step(highlight_threshold, luminance);
    
    // Apply flat highlight: either full brightness or zero (completely flat)
    // Preserve original specular color ratios
    float3 flat_highlight = specular * flat_mask;
    
    // If hardness is low, blend with original for backward compatibility
    // If hardness is high, use completely flat highlight
    if (hardness > 0.5) {
        // High hardness: completely flat (sticker-like)
        return flat_highlight;
    } else {
        // Low hardness: blend between original and flat for gradual transition
        float blend_factor = hardness * 2.0; // Scale to 0.0-1.0 range
        return lerp(specular, flat_highlight, blend_factor);
    }
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

    // Apply cartoon style effects if enabled
    if (render_settings.cartoon_enabled == 1) {
        // Quantize diffuse component
        diffuse = apply_cartoon_diffuse(diffuse, render_settings.diffuse_bands);
        // Harden specular component
        specular = apply_cartoon_specular(specular, render_settings.specular_hardness);
        
        // Note: Gradient mapping is applied in final output stage, not here
        // This preserves original color information during BRDF calculation
    }

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

// ============================================================================
// Multi-Layer Material BRDF Evaluation
// ============================================================================

float3 eval_brdf_multi_layer(
    float3 N, float3 L, float3 V,
    // Layer 1 (Base Layer) properties
    float3 albedo_layer1, float roughness_layer1, float metallic_layer1, 
    float ao_layer1, float clearcoat_layer1, float clearcoat_roughness_layer1,
    // Layer 2 (Outer Layer) properties
    float3 albedo_layer2, float roughness_layer2, float metallic_layer2,
    float ao_layer2, float clearcoat_layer2, float clearcoat_roughness_layer2,
    // Multi-layer control parameters
    float thin, float blend_factor, float layer_thickness,
    // Layer 2 alpha (for transparency support)
    float alpha_layer2
) {
    // Evaluate BRDF for both layers
    float3 brdf_layer1 = eval_brdf(N, L, V, albedo_layer1, roughness_layer1, metallic_layer1, ao_layer1, clearcoat_layer1, clearcoat_roughness_layer1);
    float3 brdf_layer2 = eval_brdf(N, L, V, albedo_layer2, roughness_layer2, metallic_layer2, ao_layer2, clearcoat_layer2, clearcoat_roughness_layer2);
    
    // Combine blend_factor with alpha_layer2 for transparency support
    // If alpha is 0 (fully transparent), show only layer 1
    // If alpha is 1 (fully opaque), use blend_factor as normal
    float effective_blend = blend_factor * alpha_layer2;
    
    // Determine if thin layer mode (thin >= 0.5) or thick layer mode (thin < 0.5)
    if (thin < 0.5) {
        // ========================================================================
        // Thick Layer Mode: Simple linear blending with alpha support
        // ========================================================================
        return lerp(brdf_layer1, brdf_layer2, effective_blend);
    } else {
        // ========================================================================
        // Thin Layer Mode: Energy-conserving optical blending
        // ========================================================================
        float NdotV = max(dot(N, V), eps);
        
        // Compute Fresnel term for layer interaction
        // Use average IOR for simplicity (can be improved with actual IOR values)
        float avg_ior = 1.45; // Default IOR
        float3 F0 = float3(0.04, 0.04, 0.04);
        float F = F_Schlick(F0, NdotV).r;
        
        // Energy-conserving blend: outer layer reflects, inner layer transmits
        // For thin layers, we consider that light can pass through the outer layer
        // Apply alpha_layer2 to control transparency
        float transmission_factor = 1.0 - F * effective_blend;
        float reflection_factor = F * effective_blend;
        
        // Blend: inner layer (transmitted) + outer layer (reflected)
        float3 final_brdf = brdf_layer1 * transmission_factor + brdf_layer2 * reflection_factor;
        
        // Ensure energy conservation
        return max(final_brdf, float3(0.0, 0.0, 0.0));
    }
}

#endif // BRDF_HLSL


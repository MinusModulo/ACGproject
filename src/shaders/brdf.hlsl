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

// ============================================================================
// Enhanced Color Effects Functions
// ============================================================================

// Calculate rim lighting effect
float3 calculate_rim_lighting(float3 normal, float3 view_dir, float rim_power, float3 rim_color) {
    if (rim_power <= 0.0) return float3(0.0, 0.0, 0.0);
    
    float rim = 1.0 - abs(dot(normal, view_dir));
    float rim_intensity = pow(rim, 1.0 / max(rim_power, 0.1));
    
    return rim_intensity * rim_color;
}

// RGB to HSV conversion
float3 rgb_to_hsv(float3 rgb) {
    float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    float4 p = lerp(float4(rgb.bg, K.wz), float4(rgb.gb, K.xy), step(rgb.b, rgb.g));
    float4 q = lerp(float4(p.xyw, rgb.r), float4(rgb.r, p.yzx), step(p.x, rgb.r));
    
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// HSV to RGB conversion
float3 hsv_to_rgb(float3 hsv) {
    float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(frac(hsv.xxx + K.xyz) * 6.0 - K.www);
    return hsv.z * lerp(K.xxx, clamp(p - K.xxx, 0.0, 1.0), hsv.y);
}

// Apply hue shift to color - AGGRESSIVE VERSION
float3 apply_hue_shift(float3 color, float strength) {
    if (strength <= 0.0) return color;
    
    float3 hsv = rgb_to_hsv(color);
    // Shift hue more aggressively
    // Use a wider hue shift range for more color variation
    float hue_shift_amount = strength * 0.15; // Shift up to 15% of hue circle
    hsv.x = frac(hsv.x + hue_shift_amount);
    
    // Also boost saturation during hue shift for more vibrant colors
    hsv.y = min(hsv.y * 1.2, 1.0);
    
    return hsv_to_rgb(hsv);
}

// Apply normal-based coloring - AGGRESSIVE VERSION
float3 apply_normal_coloring(float3 color, float3 normal, float strength) {
    if (strength <= 0.0) return color;
    
    // Create AGGRESSIVE color variation based on normal direction
    // Use normal components to create strong color shifts
    // Map normals to vibrant color tints
    float3 normal_color = float3(
        0.7 + normal.x * 0.3,  // Red tint for X direction
        0.7 + normal.y * 0.3,  // Green tint for Y direction  
        0.7 + normal.z * 0.3   // Blue tint for Z direction
    );
    
    // Add more vibrant color shifts
    float3 vibrant_tint = float3(
        1.0 + normal.x * 0.4,  // More red
        1.0 + normal.y * 0.2,  // More green
        1.0 - normal.z * 0.2   // Less blue (warmer)
    );
    
    // Blend with original color using both tints
    float3 colored1 = lerp(color, color * normal_color, strength);
    float3 colored2 = lerp(colored1, colored1 * vibrant_tint, strength * 0.5);
    
    return colored2;
}

// ============================================================================
// Anime Style Rendering (动漫风格渲染)
// ============================================================================

// Apply ultra-high saturation boost for anime style
float3 apply_anime_saturation(float3 color, float boost) {
    if (boost <= 1.0) return color;
    
    // Convert to HSV to preserve hue
    float3 hsv = rgb_to_hsv(color);
    
    // Ultra-high saturation boost (can go beyond 100% for extremely vibrant colors)
    // Clamp to 1.0 to prevent oversaturation artifacts
    float original_saturation = hsv.y;
    float boosted_saturation = min(original_saturation * boost, 1.0);
    
    // Also boost value (brightness) slightly for more vibrant appearance
    float boosted_value = min(hsv.z * 1.1, 1.0);
    
    // Reconstruct with ultra-high saturation
    float3 enhanced_hsv = float3(hsv.x, boosted_saturation, boosted_value);
    return hsv_to_rgb(enhanced_hsv);
}

// Apply rainbow mapping for colorful anime style
// Maps different areas to different hues based on position and normal
float3 apply_rainbow_mapping(float3 color, float3 position, float3 normal, float strength) {
    if (strength <= 0.0) return color;
    
    // Calculate hue offset based on position and normal
    // This creates rainbow-like color variation across the surface
    float position_factor = (position.x * 0.3 + position.y * 0.5 + position.z * 0.2) * 0.15;
    float normal_factor = (normal.x * 0.2 + normal.y * 0.6 + normal.z * 0.2) * 0.2;
    float hue_offset = (position_factor + normal_factor) * strength;
    
    // Convert to HSV and shift hue
    float3 hsv = rgb_to_hsv(color);
    hsv.x = frac(hsv.x + hue_offset);
    
    // Boost saturation during rainbow mapping for more vibrant colors
    hsv.y = min(hsv.y * 1.3, 1.0);
    
    return hsv_to_rgb(hsv);
}

// ============================================================================
// Color Bleeding Effects (插画风格藏色)
// ============================================================================

// Apply color temperature separation (色温分离) - AGGRESSIVE VERSION
// Dark areas get cool tint, bright areas get warm tint
float3 apply_color_temperature_separation(float3 color, float luminance, float strength, float3 shadow_tint, float3 highlight_tint) {
    if (strength <= 0.0) return color;
    
    // Calculate temperature factor based on luminance
    // Dark areas (low luminance) -> cool tint, bright areas (high luminance) -> warm tint
    float temperature_factor = smoothstep(0.15, 0.85, luminance);
    float3 tint = lerp(shadow_tint, highlight_tint, temperature_factor);
    
    // Apply tint AGGRESSIVELY with full strength
    float3 tinted = color * lerp(float3(1.0, 1.0, 1.0), tint, strength);
    
    // For very dark areas, add MORE cool tint
    // For bright areas, add MORE warm tint
    if (luminance < 0.4) {
        // Dark areas: add strong cool tint
        float dark_factor = (0.4 - luminance) / 0.4;
        dark_factor = pow(dark_factor, 0.8); // Make it more aggressive
        tinted = lerp(tinted, tinted * shadow_tint, dark_factor * strength * 0.6);
    } else if (luminance > 0.6) {
        // Bright areas: add strong warm tint
        float bright_factor = (luminance - 0.6) / 0.4;
        bright_factor = pow(bright_factor, 0.8); // Make it more aggressive
        tinted = lerp(tinted, tinted * highlight_tint, bright_factor * strength * 0.6);
    }
    
    return tinted;
}

// Apply complementary color bleeding (互补色藏色)
// In dark areas, blend in complementary colors for artistic effect
float3 apply_complementary_color_bleeding(float3 color, float luminance, float strength) {
    if (strength <= 0.0 || luminance > 0.4) return color; // Only apply in dark areas
    
    // Calculate complementary color (inverse of RGB)
    float3 complementary = float3(1.0, 1.0, 1.0) - color;
    
    // Blend amount increases as luminance decreases
    // The darker the area, the more complementary color is mixed in
    float blend = (0.4 - luminance) / 0.4; // 0.0 at 0.4 luminance, 1.0 at 0.0 luminance
    blend = pow(blend, 1.5); // Smooth the transition
    
    // Mix complementary color into dark areas
    return lerp(color, complementary, blend * strength);
}

// Apply gradient mapping (preserves original color hue)
float3 apply_gradient_mapping(float3 color) {
    float luminance = dot(color, float3(0.2126, 0.7152, 0.0722));
    
    // Preserve original color hue and saturation, only enhance brightness and saturation
    // Convert to HSV to preserve hue
    float3 hsv = rgb_to_hsv(color);
    float original_hue = hsv.x;
    float original_saturation = hsv.y;
    float original_value = hsv.z;
    
    // Only enhance if color has some saturation (preserve grays)
    if (original_saturation < 0.1) {
        // For low saturation colors, just boost brightness slightly
        float enhanced_value = min(original_value * 1.2, 1.0);
        return hsv_to_rgb(float3(original_hue, original_saturation, enhanced_value));
    }
    
    // For colored areas, enhance saturation and brightness AGGRESSIVELY while preserving hue
    float enhanced_saturation = min(original_saturation * 2.2, 1.0); // Boost saturation 120% for very vibrant colors
    
    // Enhance brightness more aggressively
    float enhanced_value = original_value;
    if (luminance < 0.3) {
        // Dark areas: boost significantly to bring out colors
        enhanced_value = min(original_value * 1.6, 1.0);
    } else if (luminance > 0.7) {
        // Bright areas: enhance more
        enhanced_value = min(original_value * 1.2, 1.0);
    } else {
        // Mid tones: enhance moderately
        enhanced_value = min(original_value * 1.3, 1.0);
    }
    
    // Reconstruct color with enhanced saturation and brightness but preserved hue
    float3 enhanced_hsv = float3(original_hue, enhanced_saturation, enhanced_value);
    
    return hsv_to_rgb(enhanced_hsv);
}

// Apply quantization to diffuse component for toon shading
float3 apply_cartoon_diffuse(float3 diffuse, float bands) {
    if (bands < 2.0) return diffuse; // No quantization if bands too low
    
    // Quantize based on luminance to preserve color relationships
    // This prevents color distortion that occurs when quantizing RGB channels separately
    float luminance = dot(diffuse, float3(0.2126, 0.7152, 0.0722));
    
    // Quantize luminance
    float quantized_luminance = round(luminance * bands) / bands;
    
    // Preserve color ratios while applying quantization
    // Scale the original color to match the quantized luminance
    float3 quantized = diffuse;
    if (luminance > eps) {
        float scale = quantized_luminance / luminance;
        quantized = diffuse * scale;
    }
    
    // Enhance saturation to make colors more vibrant and lively
    // Convert to HSV-like representation for saturation boost
    float max_channel = max(max(quantized.r, quantized.g), quantized.b);
    float min_channel = min(min(quantized.r, quantized.g), quantized.b);
    float saturation = (max_channel > eps) ? (max_channel - min_channel) / max_channel : 0.0;
    
    // Boost saturation AGGRESSIVELY to make colors extremely vibrant
    // This helps preserve the red, yellow, black color scheme
    float saturation_boost = 2.5; // 150% saturation boost for extremely vibrant colors
    float new_saturation = min(saturation * saturation_boost, 1.0);
    
    // Reconstruct color with enhanced saturation
    if (max_channel > eps && saturation > 0.01) {
        float3 gray = float3(quantized_luminance, quantized_luminance, quantized_luminance);
        quantized = lerp(gray, quantized, new_saturation / max(saturation, 0.01));
    }
    
    // Apply AGGRESSIVE color enhancement: boost color intensity significantly
    // This helps bring out red, yellow colors that might be too subtle
    if (saturation > 0.05) {
        // For colored areas, boost the color channels significantly
        float color_boost = 1.6; // 60% color boost for more vibrant colors
        quantized = lerp(quantized, quantized * color_boost, saturation * 0.8);
    }
    
    return quantized;
}

// Apply hardening to specular component for cartoon highlight
float3 apply_cartoon_specular(float3 specular, float hardness) {
    if (hardness <= 0.0) return specular;

    float luminance = dot(specular, float3(0.2126, 0.7152, 0.0722));
    
    // Use much higher threshold to only harden very bright highlights
    // Threshold range: 0.5-1.5 based on hardness (higher = more selective)
    // This ensures we only affect true specular highlights, not diffuse reflections
    float threshold = lerp(0.5, 1.5, hardness);
    float width = lerp(0.15, 0.05, hardness); // Narrower transition for higher hardness
    
    // Only apply hardening to areas above threshold
    // This prevents affecting diffuse areas that might have some specular component
    if (luminance < threshold - width) {
        // Below threshold: return original specular (no hardening)
        return specular;
    }
    
    // Create a mask for the hardening transition
    float mask = smoothstep(threshold - width, threshold + width, luminance);
    
    // For high hardness, use step function for hard cutoff
    // For lower hardness, use smoothstep for gradual transition
    float hardened_mask;
    if (hardness > 0.6) {
        // Hard cutoff for high hardness values
        hardened_mask = step(threshold, luminance);
    } else {
        // Smooth transition for lower hardness
        hardened_mask = mask;
    }
    
    // Preserve original specular color, but harden the transition
    // Only apply hardening to the bright highlight areas
    float3 hardened_specular = specular * hardened_mask;
    
    // Blend between original and hardened based on mask strength
    // This ensures we only modify the bright highlight areas
    return lerp(specular, hardened_specular, mask * hardness);
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


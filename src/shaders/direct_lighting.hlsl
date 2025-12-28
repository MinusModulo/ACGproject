// ============================================================================
// Direct_Lighting.hlsl - 直接光照计算模块
// ============================================================================

#ifndef DIRECT_LIGHTING_HLSL
#define DIRECT_LIGHTING_HLSL

#include "common.hlsl"
#include "light_sampling.hlsl"
#include "shadow.hlsl"
#include "brdf.hlsl"
#include "sampling.hlsl"

// ============================================================================
// MIS Weight Functions
// ============================================================================

// Balance Heuristic: w_i = p_i / (p_1 + p_2)
float mis_weight_balance(float pdf_a, float pdf_b) {
    float pdf_sum = pdf_a + pdf_b;
    return pdf_sum > eps ? (pdf_a / pdf_sum) : 0.5;
}

// Power Heuristic: w_i = (p_i)^β / ((p_1)^β + (p_2)^β)
float mis_weight_power(float pdf_a, float pdf_b, float beta = 2.0) {
    float pdf_a_pow = pow(max(pdf_a, eps), beta);
    float pdf_b_pow = pow(max(pdf_b, eps), beta);
    float pdf_sum = pdf_a_pow + pdf_b_pow;
    return pdf_sum > eps ? (pdf_a_pow / pdf_sum) : 0.5;
}

// ========================================================================
// Firefly Reduction: Safe Power Heuristic (Scheme 4)
// ========================================================================
// Power heuristic with safety checks to prevent fireflies
float mis_weight_power_safe(float pdf_a, float pdf_b, float beta = 2.0) {
    // Prevent PDF from being 0 or too small
    pdf_a = max(pdf_a, eps);
    pdf_b = max(pdf_b, eps);
    
    // If PDF ratio is too extreme, use conservative strategy
    float ratio = pdf_a / pdf_b;
    if (ratio > 100.0 || ratio < 0.01) {
        // PDF difference too large, use the larger one only
        return (pdf_a > pdf_b) ? 1.0 : 0.0;
    }
    
    // Power heuristic (β=2)
    float pdf_a_pow = pdf_a * pdf_a; // Use multiplication instead of pow for performance
    float pdf_b_pow = pdf_b * pdf_b;
    float pdf_sum = pdf_a_pow + pdf_b_pow;
    return pdf_sum > eps ? (pdf_a_pow / pdf_sum) : 0.5;
}

// ============================================================================
// Direct Lighting with MIS (Light + BRDF Sampling)
// ============================================================================

float3 EvaluateLight(Light light, float3 position, float3 normal, float3 view_dir, float3 albedo, float roughness, float metallic, float ao, float clearcoat, float clearcoat_roughness, inout uint rng_state) {
  float3 direct_light = float3(0.0, 0.0, 0.0);
  
  // ========================================================================
  // Strategy 1: Light Sampling (NEE)
  // ========================================================================
  float3 light_dir;
  float3 radiance_light;
  float inv_pdf_light;
  float pdf_light = 0.0;
  float max_distance = 0.0;
  float3 contribution_light = float3(0.0, 0.0, 0.0);
  bool light_sample_valid = false;
  
  if (light.type == 0) {
    radiance_light = SamplePointLight(light, position, light_dir, inv_pdf_light);
    // For point lights, inv_pdf = 1.0, so pdf = 1.0 (delta distribution)
    pdf_light = 1.0;
    max_distance = length(light.position - position);
  } else if (light.type == 2) {
    radiance_light = SampleSunLight(light, light_dir, inv_pdf_light, rng_state);
    pdf_light = 1.0 / max(inv_pdf_light, eps);
    max_distance = 1e9; // effectively infinite
  } else if (light.type == 1) {
    float3 sampled_point;
    radiance_light = SampleAreaLight(light, position, light_dir, inv_pdf_light, sampled_point, rng_state);
    // For area lights, inv_pdf = area * cos_theta / dist_sq, so pdf = dist_sq / (area * cos_theta)
    pdf_light = 1.0 / max(inv_pdf_light, eps);
    max_distance = length(sampled_point - position);
  }
  
  float NdotL_light = max(dot(normal, light_dir), 0.0);
  if (NdotL_light > 0.0) {
    // ========================================================================
    // Firefly Reduction: Dynamic Roughness Clamping (Scheme 1)
    // ========================================================================
    // Calculate light solid angle to determine appropriate roughness clamping
    float light_solid_angle = 0.0;
    if (light.type == 0) {
      // Point light: use fixed small angle
      light_solid_angle = 0.01; // ~0.57 degrees
    } else if (light.type == 2) {
      float theta = max(light.angular_radius, 1e-4);
      light_solid_angle = 2.0 * PI * (1.0 - cos(theta));
    } else if (light.type == 1) {
      // Area light: calculate actual solid angle
      float area = length(cross(light.u, light.v));
      float dist_sq = max(dot(light.position - position, light.position - position), 0.01);
      light_solid_angle = area / dist_sq;
    }
    
    // Dynamic roughness clamping based on light size
    // Smaller lights need larger roughness to reduce fireflies
    float min_roughness = 0.15;
    if (light_solid_angle < 0.1) {
      // Small light: increase minimum roughness
      min_roughness = clamp(0.15 / sqrt(max(light_solid_angle * 10.0, 0.1)), 0.15, 0.4);
    }
    
    float safe_roughness = max(roughness, min_roughness);
    float3 brdf_light = eval_brdf(normal, light_dir, view_dir, albedo, safe_roughness, metallic, ao, clearcoat, clearcoat_roughness);
    if (!CastShadowRay(position + normal * 1e-3, light_dir, max_distance - 1e-3)) {
      contribution_light = brdf_light * radiance_light * NdotL_light;
      
      // ========================================================================
      // Firefly Reduction: Contribution Clamping (Scheme 3)
      // ========================================================================
      // Clamp contribution to prevent fireflies (safety net)
      float max_contribution = 20.0; // Adjust based on scene
      contribution_light = min(contribution_light, float3(max_contribution, max_contribution, max_contribution));
      
      light_sample_valid = true;
    }
  }
  
  // ========================================================================
  // Strategy 2: BRDF Sampling (check if direction hits light)
  // ========================================================================
  float3 contribution_brdf = float3(0.0, 0.0, 0.0);
  float pdf_brdf = 0.0;
  bool brdf_sample_valid = false;
  
  // Sample direction from BRDF
  float r1 = rand(rng_state);
  float r2 = rand(rng_state);
  float r3 = rand(rng_state);
  
  // Build tangent frame
  float3 up = abs(normal.z) < 0.999 ? float3(0, 0, 1) : float3(1, 0, 0);
  float3 tangent = normalize(cross(up, normal));
  float3 bitangent = cross(normal, tangent);
  
  // Calculate selection probabilities (same as in shader.hlsl)
  float3 F0 = lerp(float3(0.04, 0.04, 0.04), albedo, metallic);
  float3 F = F_Schlick(F0, max(dot(normal, view_dir), 0.0));
  float luminance = dot(F, float3(0.2126, 0.7152, 0.0722));
  
  float q_spec_base = clamp(saturate(luminance), 0.05, 0.95);
  float q_diff_base = 1.0 - q_spec_base;
  
  float p_clearcoat = 0.0;
  if (clearcoat > 0.0) {
    float F_cc = F_Schlick(float3(0.04, 0.04, 0.04), max(dot(normal, view_dir), 0.0)).r;
    p_clearcoat = clamp(clearcoat * 0.5, 0.0, 0.5);
  }
  float p_base = 1.0 - p_clearcoat;
  
  // Sample direction from BRDF
  float3 brdf_dir;
  if (r3 < p_clearcoat) {
    // Sample clearcoat specular
    float r4 = rand(rng_state);
    float r5 = rand(rng_state);
    float3 h_local = sample_GGX_half(r4, r5, clearcoat_roughness);
    float3 H = h_local.x * tangent + h_local.y * bitangent + h_local.z * normal;
    H = normalize(H);
    brdf_dir = normalize(reflect(-view_dir, H));
  } else {
    float r3_base = (r3 - p_clearcoat) / max(eps, p_base);
    if (r3_base < q_spec_base) {
      // Sample base specular
      float r4 = rand(rng_state);
      float r5 = rand(rng_state);
      float3 h_local = sample_GGX_half(r4, r5, roughness);
      float3 H = h_local.x * tangent + h_local.y * bitangent + h_local.z * normal;
      H = normalize(H);
      brdf_dir = normalize(reflect(-view_dir, H));
    } else {
      // Sample diffuse
      float3 local_diff = sample_cosine_hemisphere(r1, r2);
      brdf_dir = local_diff.x * tangent + local_diff.y * bitangent + local_diff.z * normal;
      brdf_dir = normalize(brdf_dir);
    }
  }
  
  float NdotL_brdf = max(dot(normal, brdf_dir), 0.0);
  if (NdotL_brdf > 0.0) {
    // Check if BRDF direction hits the light
    float3 brdf_to_light = (light.type == 0) ?
      normalize(light.position - position) :
      ((light.type == 2) ? normalize(-light.direction) : normalize(light.position - position));
    
    float cos_angle = dot(brdf_dir, brdf_to_light);
    
    // For point lights: check if direction is close enough
    // For area lights: check if direction intersects the light area
    bool hits_light = false;
    if (light.type == 0) {
      // Point light: check if direction is close (within small angle)
      hits_light = cos_angle > 0.99; // ~8 degrees
    } else if (light.type == 2) {
      float cos_theta_max = cos(max(light.angular_radius, 1e-4));
      hits_light = cos_angle >= cos_theta_max;
    } else if (light.type == 1) {
      // Area light: check if ray intersects the light plane
      // Simplified: check if direction is roughly towards light center
      hits_light = cos_angle > 0.9; // ~25 degrees (more lenient for area lights)
    }
    
    if (hits_light) {
      // Calculate light radiance for this direction
      float3 light_radiance_brdf = float3(0.0, 0.0, 0.0);
      float dist_to_light = 0.0;
      
      if (light.type == 0) {
        dist_to_light = length(light.position - position);
        float dist_sq = dist_to_light * dist_to_light;
        light_radiance_brdf = light.color * light.intensity / dist_sq;
      } else if (light.type == 2) {
        dist_to_light = 1e9; // effectively infinite
        light_radiance_brdf = light.color * light.intensity;
      } else if (light.type == 1) {
        // For area lights, use average distance and radiance
        dist_to_light = length(light.position - position);
        light_radiance_brdf = light.color * light.intensity;
      }
      
      if (!CastShadowRay(position + normal * 1e-3, brdf_dir, dist_to_light - 1e-3)) {
        float safe_roughness = max(roughness, 0.15);
        float3 brdf_brdf = eval_brdf(normal, brdf_dir, view_dir, albedo, safe_roughness, metallic, ao, clearcoat, clearcoat_roughness);
        contribution_brdf = brdf_brdf * light_radiance_brdf * NdotL_brdf;
        
        // ========================================================================
        // Firefly Reduction: Contribution Clamping (Scheme 3)
        // ========================================================================
        float max_contribution = 20.0; // Adjust based on scene
        contribution_brdf = min(contribution_brdf, float3(max_contribution, max_contribution, max_contribution));
        
        pdf_brdf = pdf_brdf_for_direction(normal, view_dir, brdf_dir, roughness, metallic, clearcoat, clearcoat_roughness);
        brdf_sample_valid = true;
      }
    }
  }
  
  // ========================================================================
  // Combine contributions using MIS
  // ========================================================================
  if (light_sample_valid) {
    // Point lights remain delta; sun and area participate in MIS
    if (light.type == 0) {
      direct_light += contribution_light;
    } else {
      float pdf_light_actual = pdf_light;
      float pdf_brdf_for_light_dir = pdf_brdf_for_direction(normal, view_dir, light_dir, roughness, metallic, clearcoat, clearcoat_roughness);

      float w_light = mis_weight_power_safe(pdf_light_actual, pdf_brdf_for_light_dir);

      direct_light += w_light * contribution_light / max(pdf_light_actual, eps);
    }
  }
  
  if (brdf_sample_valid) {
    // Calculate PDFs for MIS
    float pdf_brdf_actual = pdf_brdf;
    float pdf_light_for_brdf_dir = pdf_light_for_direction(light, position, brdf_dir);
    
    // ========================================================================
    // Firefly Reduction: Use Safe Power Heuristic (Scheme 4)
    // ========================================================================
    float w_brdf = mis_weight_power_safe(pdf_brdf_actual, pdf_light_for_brdf_dir);
    direct_light += w_brdf * contribution_brdf / max(pdf_brdf_actual, eps);
  }
  
  return direct_light;
}

// ============================================================================
// Multi-Layer Material Direct Lighting Evaluation
// ============================================================================

// Calculate PDF for multi-layer BRDF (simplified: use layer 1 for PDF calculation)
float pdf_brdf_multi_layer_for_direction(
    float3 N, float3 V, float3 L,
    float roughness_layer1, float metallic_layer1, float clearcoat_layer1, float clearcoat_roughness_layer1
) {
    // For multi-layer materials, we use layer 1's PDF (can be improved)
    return pdf_brdf_for_direction(N, V, L, roughness_layer1, metallic_layer1, clearcoat_layer1, clearcoat_roughness_layer1);
}

float3 EvaluateLightMultiLayer(
    Light light, float3 position, float3 normal, float3 view_dir,
    // Layer 1 properties
    float3 albedo_layer1, float roughness_layer1, float metallic_layer1,
    float ao_layer1, float clearcoat_layer1, float clearcoat_roughness_layer1,
    // Layer 2 properties
    float3 albedo_layer2, float roughness_layer2, float metallic_layer2,
    float ao_layer2, float clearcoat_layer2, float clearcoat_roughness_layer2,
    // Multi-layer control
    float thin, float blend_factor, float layer_thickness,
    float alpha_layer2,  // Layer 2 alpha for transparency
    inout uint rng_state
) {
    float3 direct_light = float3(0.0, 0.0, 0.0);
    
    // ========================================================================
    // Strategy 1: Light Sampling (NEE)
    // ========================================================================
    float3 light_dir;
    float3 radiance_light;
    float inv_pdf_light;
    float pdf_light = 0.0;
    float max_distance = 0.0;
    float3 contribution_light = float3(0.0, 0.0, 0.0);
    bool light_sample_valid = false;
    
    if (light.type == 0) {
      radiance_light = SamplePointLight(light, position, light_dir, inv_pdf_light);
      pdf_light = 1.0;
      max_distance = length(light.position - position);
    } else if (light.type == 2) {
      radiance_light = SampleSunLight(light, light_dir, inv_pdf_light, rng_state);
      pdf_light = 1.0 / max(inv_pdf_light, eps);
      max_distance = 1e9;
    } else if (light.type == 1) {
        float3 sampled_point;
        radiance_light = SampleAreaLight(light, position, light_dir, inv_pdf_light, sampled_point, rng_state);
        pdf_light = 1.0 / max(inv_pdf_light, eps);
        max_distance = length(sampled_point - position);
    }
    
    float NdotL_light = max(dot(normal, light_dir), 0.0);
    if (NdotL_light > 0.0) {
        // ========================================================================
        // Firefly Reduction: Dynamic Roughness Clamping (Scheme 1)
        // ========================================================================
        // Calculate light solid angle to determine appropriate roughness clamping
        float light_solid_angle = 0.0;
        if (light.type == 0) {
          light_solid_angle = 0.01; // ~0.57 degrees
        } else if (light.type == 2) {
          float theta = max(light.angular_radius, 1e-4);
          light_solid_angle = 2.0 * PI * (1.0 - cos(theta));
        } else if (light.type == 1) {
            float area = length(cross(light.u, light.v));
            float dist_sq = max(dot(light.position - position, light.position - position), 0.01);
            light_solid_angle = area / dist_sq;
        }
        
        // Dynamic roughness clamping based on light size
        float min_roughness = 0.15;
        if (light_solid_angle < 0.1) {
            min_roughness = clamp(0.15 / sqrt(max(light_solid_angle * 10.0, 0.1)), 0.15, 0.4);
        }
        
        float safe_roughness_layer1 = max(roughness_layer1, min_roughness);
        float safe_roughness_layer2 = max(roughness_layer2, min_roughness);
        
        float3 brdf_light = eval_brdf_multi_layer(
            normal, light_dir, view_dir,
            albedo_layer1, safe_roughness_layer1, metallic_layer1,
            ao_layer1, clearcoat_layer1, clearcoat_roughness_layer1,
            albedo_layer2, safe_roughness_layer2, metallic_layer2,
            ao_layer2, clearcoat_layer2, clearcoat_roughness_layer2,
            thin, blend_factor, layer_thickness,
            alpha_layer2
        );
        
        if (!CastShadowRay(position + normal * 1e-3, light_dir, max_distance - 1e-3)) {
            contribution_light = brdf_light * radiance_light * NdotL_light;
            
            // ========================================================================
            // Firefly Reduction: Contribution Clamping (Scheme 3)
            // ========================================================================
            float max_contribution = 20.0; // Adjust based on scene
            contribution_light = min(contribution_light, float3(max_contribution, max_contribution, max_contribution));
            
            light_sample_valid = true;
        }
    }
    
    // ========================================================================
    // Strategy 2: BRDF Sampling (check if direction hits light)
    // ========================================================================
    float3 contribution_brdf = float3(0.0, 0.0, 0.0);
    float pdf_brdf = 0.0;
    bool brdf_sample_valid = false;
    
    // Sample direction from BRDF (use layer 1 for sampling strategy)
    float r1 = rand(rng_state);
    float r2 = rand(rng_state);
    float r3 = rand(rng_state);
    
    // Build tangent frame
    float3 up = abs(normal.z) < 0.999 ? float3(0, 0, 1) : float3(1, 0, 0);
    float3 tangent = normalize(cross(up, normal));
    float3 bitangent = cross(normal, tangent);
    
    // Calculate selection probabilities (use layer 1)
    float3 F0 = lerp(float3(0.04, 0.04, 0.04), albedo_layer1, metallic_layer1);
    float3 F = F_Schlick(F0, max(dot(normal, view_dir), 0.0));
    float luminance = dot(F, float3(0.2126, 0.7152, 0.0722));
    
    float q_spec_base = clamp(saturate(luminance), 0.05, 0.95);
    float q_diff_base = 1.0 - q_spec_base;
    
    float p_clearcoat = 0.0;
    if (clearcoat_layer1 > 0.0) {
        float F_cc = F_Schlick(float3(0.04, 0.04, 0.04), max(dot(normal, view_dir), 0.0)).r;
        p_clearcoat = clamp(clearcoat_layer1 * 0.5, 0.0, 0.5);
    }
    float p_base = 1.0 - p_clearcoat;
    
    // Sample direction from BRDF
    float3 brdf_dir;
    if (r3 < p_clearcoat) {
        float r4 = rand(rng_state);
        float r5 = rand(rng_state);
        float3 h_local = sample_GGX_half(r4, r5, clearcoat_roughness_layer1);
        float3 H = h_local.x * tangent + h_local.y * bitangent + h_local.z * normal;
        H = normalize(H);
        brdf_dir = normalize(reflect(-view_dir, H));
    } else {
        float r3_base = (r3 - p_clearcoat) / max(eps, p_base);
        if (r3_base < q_spec_base) {
            float r4 = rand(rng_state);
            float r5 = rand(rng_state);
            float3 h_local = sample_GGX_half(r4, r5, roughness_layer1);
            float3 H = h_local.x * tangent + h_local.y * bitangent + h_local.z * normal;
            H = normalize(H);
            brdf_dir = normalize(reflect(-view_dir, H));
        } else {
            float3 local_diff = sample_cosine_hemisphere(r1, r2);
            brdf_dir = local_diff.x * tangent + local_diff.y * bitangent + local_diff.z * normal;
            brdf_dir = normalize(brdf_dir);
        }
    }
    
    float NdotL_brdf = max(dot(normal, brdf_dir), 0.0);
    if (NdotL_brdf > 0.0) {
      float3 brdf_to_light = (light.type == 2) ? normalize(-light.direction) : normalize(light.position - position);
        float cos_angle = dot(brdf_dir, brdf_to_light);
        
        bool hits_light = false;
        if (light.type == 0) {
            hits_light = cos_angle > 0.99;
      } else if (light.type == 2) {
        float cos_theta_max = cos(max(light.angular_radius, 1e-4));
        hits_light = cos_angle >= cos_theta_max;
        } else if (light.type == 1) {
            hits_light = cos_angle > 0.9;
        }
        
        if (hits_light) {
            float3 light_radiance_brdf = float3(0.0, 0.0, 0.0);
            float dist_to_light = 0.0;
            
            if (light.type == 0) {
              dist_to_light = length(light.position - position);
              float dist_sq = dist_to_light * dist_to_light;
              light_radiance_brdf = light.color * light.intensity / dist_sq;
            } else if (light.type == 2) {
              dist_to_light = 1e9;
              light_radiance_brdf = light.color * light.intensity;
            } else if (light.type == 1) {
              dist_to_light = length(light.position - position);
              light_radiance_brdf = light.color * light.intensity;
            }
            
            if (!CastShadowRay(position + normal * 1e-3, brdf_dir, dist_to_light - 1e-3)) {
                float safe_roughness_layer1 = max(roughness_layer1, 0.15);
                float safe_roughness_layer2 = max(roughness_layer2, 0.15);
                
                float3 brdf_brdf = eval_brdf_multi_layer(
                    normal, brdf_dir, view_dir,
                    albedo_layer1, safe_roughness_layer1, metallic_layer1,
                    ao_layer1, clearcoat_layer1, clearcoat_roughness_layer1,
                    albedo_layer2, safe_roughness_layer2, metallic_layer2,
                    ao_layer2, clearcoat_layer2, clearcoat_roughness_layer2,
                    thin, blend_factor, layer_thickness,
                    alpha_layer2
                );
                
                contribution_brdf = brdf_brdf * light_radiance_brdf * NdotL_brdf;
                
                // ========================================================================
                // Firefly Reduction: Contribution Clamping (Scheme 3)
                // ========================================================================
                float max_contribution = 20.0; // Adjust based on scene
                contribution_brdf = min(contribution_brdf, float3(max_contribution, max_contribution, max_contribution));
                
                pdf_brdf = pdf_brdf_multi_layer_for_direction(normal, view_dir, brdf_dir, roughness_layer1, metallic_layer1, clearcoat_layer1, clearcoat_roughness_layer1);
                brdf_sample_valid = true;
            }
        }
    }
    
    // ========================================================================
    // Combine contributions using MIS
    // ========================================================================
    if (light_sample_valid) {
        // For point lights, use original NEE formula (delta distribution, no MIS needed)
      if (light.type == 0) {
        // Delta lights: use original formula (inv_pdf = 1.0)
            direct_light += contribution_light;
        } else {
            // Area light: use MIS with safe power heuristic
            float pdf_light_actual = pdf_light;
            float pdf_brdf_for_light_dir = pdf_brdf_multi_layer_for_direction(normal, view_dir, light_dir, roughness_layer1, metallic_layer1, clearcoat_layer1, clearcoat_roughness_layer1);
            
            // ========================================================================
            // Firefly Reduction: Use Safe Power Heuristic (Scheme 4)
            // ========================================================================
            float w_light = mis_weight_power_safe(pdf_light_actual, pdf_brdf_for_light_dir);
            
            direct_light += w_light * contribution_light / max(pdf_light_actual, eps);
        }
    }
    
    if (brdf_sample_valid) {
        // Calculate PDFs for MIS
        float pdf_brdf_actual = pdf_brdf;
        float pdf_light_for_brdf_dir = pdf_light_for_direction(light, position, brdf_dir);
        
        // ========================================================================
        // Firefly Reduction: Use Safe Power Heuristic (Scheme 4)
        // ========================================================================
        float w_brdf = mis_weight_power_safe(pdf_brdf_actual, pdf_light_for_brdf_dir);
        direct_light += w_brdf * contribution_brdf / max(pdf_brdf_actual, eps);
    }
    
    return direct_light;
}

#endif // DIRECT_LIGHTING_HLSL


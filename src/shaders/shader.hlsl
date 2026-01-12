// ============================================================================
// Shader.hlsl - 主着色器文件
// 路径追踪渲染器的入口点
// ============================================================================

// 包含所有模块
#include "common.hlsl"
#include "rng.hlsl"
#include "brdf.hlsl"
#include "sampling.hlsl"
#include "light_sampling.hlsl"
#include "shadow.hlsl"
#include "direct_lighting.hlsl"
#include "volume.hlsl"

bool dead() {
  int i = 2;
  while (i >= 0) {
    if (i == 2) i -= 2;
    else i += 2;
  }
  return true;
}

float3 ACESFilm(float3 x) {
    float a = 2.51f;
    float b = 0.03f;
    float c = 2.43f;
    float d = 0.59f;
    float e = 0.14f;
    return saturate((x*(a*x+b))/(x*(c*x+d)+e));
}

// ============================================================================
// Ray Generation Shader - 路径追踪主循环
// ============================================================================

[shader("raygeneration")] void RayGenMain() {
  uint2 pixel_coords = DispatchRaysIndex().xy;
  int frame_count = accumulated_samples[pixel_coords];

  // we hash the state with both pixel coordinates and frame count
  uint rng_state = wang_hash((pixel_coords.x + pixel_coords.y * DispatchRaysDimensions().x) * 666 + 1919810) ^ wang_hash(frame_count * 233 + 114514);

  // The calculating uv, d, origin, target and direction part remains the same
  // Jitter the pixel position for anti-aliasing
  float2 jitter = float2(rand(rng_state), rand(rng_state));
  float2 pixel_center = (float2)DispatchRaysIndex() + jitter;
  float2 uv = pixel_center / float2(DispatchRaysDimensions().xy);
  uv.y = 1.0 - uv.y;
  float2 d = uv * 2.0 - 1.0;
  float4 origin = mul(camera_info.camera_to_world, float4(0, 0, 0, 1));
  float4 target = mul(camera_info.screen_to_camera, float4(d, 1, 1));
  float4 direction = mul(camera_info.camera_to_world, float4(target.xyz, 0));

  // The ray init part remains the same
  float t_min = eps;
  float t_max = 1e4;
  RayDesc ray;
  ray.Origin = origin.xyz;
  ray.Direction = normalize(direction.xyz);
  ray.TMin = t_min;
  ray.TMax = t_max;

  RayPayload payload;
  float3 throughput = float3(1.0, 1.0, 1.0);
  float3 radiance = float3(0.0, 0.0, 0.0);
  payload.rng_state = rng_state;

  // core of path tracing

  int depth = 0;
  int max_depth = max(render_settings.max_bounces, 1);
  
  while (depth < max_depth) {

    // we trace a ray
    payload.hit = false;
    TraceRay(as, RAY_FLAG_NONE, 0xFF, 0, 1, 0, ray, payload);

    rng_state = payload.rng_state; 
    // TraceRay -> ClosestHitMain -> EvaluateLight -> rand -> rand_xorshift changes rng_state

    // record the id of this entity, if hit
    if (depth == 0) {
      entity_id_output[pixel_coords] = payload.hit ? (int)payload.instance_id : -1;
    }

    // ========================================================================
    // Homogeneous Volume Rendering (Restricted to Bounding Box)
    // ========================================================================
    // VolumeRegion vol;
    // // Define a bounding box around the area light (approx pos: 2.4, 1.2, 1.0)
    // vol.min_p = float3(1.4, 0.2, 0.0);
    // vol.max_p = float3(3.4, 2.2, 2.0);
    // vol.sigma_t = 0.2; // Density
    // vol.sigma_s = float3(0.2, 0.2, 0.2); // Scattering albedo (white fog)

    float hit_dist = payload.hit ? distance(ray.Origin, payload.position) : 1e10;
    
    VolumeRegion vol;
    vol.min_p = volume_info.min_p;
    vol.max_p = volume_info.max_p;
    vol.sigma_t = volume_info.sigma_t;
    vol.sigma_s = volume_info.sigma_s;
    vol.pad0 = 0;
    vol.pad1 = 0;

    if (SampleHomogeneousVolume(ray, throughput, rng_state, vol, hit_dist)) {
        depth++;
        payload.rng_state = rng_state;
        continue;
    }
    // ========================================================================

    // if not hit, accumulate sky color and break
    if (!payload.hit) {
      radiance += throughput * payload.emission;
      break;
    }

    radiance += throughput * payload.emission; // emissive term
    
    // ========================================================================
    // Firefly Reduction: Indirect Light Clamping
    // ========================================================================
    float3 bounce_light = payload.direct_light;
    if (depth > 0) {
        float indirect_clamp = 10.0;
        bounce_light = min(bounce_light, float3(indirect_clamp, indirect_clamp, indirect_clamp));
    }
    radiance += throughput * bounce_light; // direct lighting

    // transmission
    if (payload.transmission > 0.0) {
      // randomly choose transmission or not
      if (rand(rng_state) < payload.transmission) {
        // Get N and V
        float3 N = payload.normal;
        float3 V = -normalize(ray.Direction);
        
        // get eta, the index of refraction
        float eta = payload.front_face ? (1.0 / payload.ior) : (payload.ior);
        
        // Fresnel (this is true)
        float F0 = (1.0 - payload.ior) / (1.0 + payload.ior);
        F0 = F0 * F0;
        float F = F0 + (1.0 - F0) * pow(1.0 - dot(N, V), 5.0);
        
        // get refraction direction
        float3 I = ray.Direction;
        float3 refract_dir = refract(I, N, eta);
        
        // check for total internal reflection
        if (length(refract_dir) < 0.001) {
          F = 1.0;
        }
        
        if (rand(rng_state) < F) {
            // reflection
            float3 reflect_dir = reflect(I, N);
            ray.Origin = payload.position + N * eps;
            ray.Direction = normalize(reflect_dir);
            // you get full albedo on reflection
        } else {
            // refraction

            float ior_to_use = payload.ior;
            float3 color_mask = float3(1.0, 1.0, 1.0);
            float weight_correction = 1.0;

            if (payload.dispersion > 0.0) {
              float r_channel = rand(rng_state);
              if (r_channel < 1.0 / 3.0) {
                ior_to_use = payload.ior + payload.dispersion * 0.02;
                color_mask = float3(1.0, 0.0, 0.0);
              } else if (r_channel < 2.0 / 3.0) {
                ior_to_use = payload.ior;
                color_mask = float3(0.0, 1.0, 0.0);
              } else {
                ior_to_use = payload.ior - payload.dispersion * 0.02;
                color_mask = float3(0.0, 0.0, 1.0);
              }
              weight_correction = 3.0;
            }
            float eta_disp = payload.front_face ? (1.0 / ior_to_use) : (ior_to_use);
            float3 refract_dir = refract(I, N, eta_disp);
            if (length(refract_dir) < 0.001) {
                // total internal reflection fallback
                float3 reflect_dir = reflect(I, N);
                ray.Origin = payload.position + N * eps;
                ray.Direction = normalize(reflect_dir);
            } else {
                ray.Origin = payload.position - N * eps;
                ray.Direction = normalize(refract_dir);
            }
            throughput *= payload.albedo;
            throughput *= color_mask * weight_correction;
        }

        // weighting
        throughput /= payload.transmission;
        
        float p =  saturate(max(throughput.x, max(throughput.y, throughput.z)));
        p = clamp(p, 0.05, 0.95);
        if (rand(rng_state) > p) break;
        throughput /= p;
        depth += 1;
        payload.rng_state = rng_state;
        continue; // skip opaque, so if transmission chosen, it's not metallic, rough, etc.
      } else {
        // Normalize throughput for not choosing transmission
        throughput /= (1.0 - payload.transmission);
      }
    }

    // alphaMode test :
    if (payload.alpha_mode == 2) { // BLEND
      if (rand(rng_state) > payload.alpha) {
        // skip this intersection, continue tracing
        ray.Origin = payload.position + ray.Direction * payload.new_eps;
        depth += 1;
        continue;
      }
    } else if (payload.alpha_mode == 1) { // MASK
      if (payload.alpha < 0.5) {
        // skip this intersection, continue tracing
        ray.Origin = payload.position + ray.Direction * payload.new_eps;
        depth += 1;
        continue;
      }
    }

    // otherwise, let N be the normal
    float3 N = payload.normal;
    
    // ========================================================================
    // Firefly Reduction: Roughness Floor (Filter Glossy)
    // ========================================================================
    // Apply roughness floor for indirect bounces to prevent singular spikes
    float roughness_floor = (depth > 0) ? 0.1 : 0.0;
    float eff_roughness = max(payload.roughness, roughness_floor);
    float eff_clearcoat_roughness = max(payload.clearcoat_roughness, roughness_floor);
    float eff_roughness_layer2 = max(payload.roughness_layer2, roughness_floor);
    float eff_clearcoat_roughness_layer2 = max(payload.clearcoat_roughness_layer2, roughness_floor);

    // sample randoms
    float r1 = rand(rng_state);
    float r2 = rand(rng_state);
    float r3 = rand(rng_state); // choose strategy

    // build tangent frame
    float3 up = abs(N.z) < 0.999 ? float3(0, 0, 1) : float3(1, 0, 0);
    float3 tangent = normalize(cross(up, N));
    float3 bitangent = cross(N, tangent);

    // V is the in-direction (with a negative)
    float3 V = -normalize(ray.Direction);

    // Calculate selection probabilities
    float3 F0 = lerp(float3(0.04, 0.04, 0.04), payload.albedo, payload.metallic);
    float3 F = F_Schlick(F0, dot(N, V));
    float luminance = dot(F, float3(0.2126, 0.7152, 0.0722));
    
    // Base layer probabilities
    float q_spec_base = clamp(saturate(luminance), 0.05, 0.95);
    float q_diff_base = 1.0 - q_spec_base;

    // Clearcoat probability
    float p_clearcoat = 0.0;
    if (payload.clearcoat > 0.0) {
        float F_cc = F_Schlick(float3(0.04, 0.04, 0.04), dot(N, V)).r;
        p_clearcoat = clamp(payload.clearcoat * 0.5, 0.0, 0.5); // Simple fixed weight based on strength
    }
    float p_base = 1.0 - p_clearcoat;

    // Generate candidates
    
    // Diffuse candidate
    float3 local_diff = sample_cosine_hemisphere(r1, r2);
    float3 L_diff = local_diff.x * tangent + local_diff.y * bitangent + local_diff.z * N;
    L_diff = normalize(L_diff);
    
    // Base Specular candidate
    float r4 = rand(rng_state);
    float r5 = rand(rng_state);
    float3 h_local = sample_GGX_half(r4, r5, eff_roughness);
    float3 H_base = h_local.x * tangent + h_local.y * bitangent + h_local.z * N;
    H_base = normalize(H_base);
    float3 L_spec_base = normalize(reflect(-V, H_base));

    // Clearcoat Specular candidate
    float r6 = rand(rng_state);
    float r7 = rand(rng_state);
    float3 h_local_cc = sample_GGX_half(r6, r7, eff_clearcoat_roughness);
    float3 H_cc = h_local_cc.x * tangent + h_local_cc.y * bitangent + h_local_cc.z * N;
    H_cc = normalize(H_cc);
    float3 L_spec_cc = normalize(reflect(-V, H_cc));

    // Select direction
    float3 next_dir;
    if (r3 < p_clearcoat) {
        next_dir = L_spec_cc;
    } else {
        // Rescale r3 to [0, 1] for base selection
        float r3_base = (r3 - p_clearcoat) / max(eps, p_base);
        if (r3_base < q_spec_base) {
            next_dir = L_spec_base;
        } else {
            next_dir = L_diff;
        }
    }

    // Calculate combined PDF
    float pdf_diff = max(dot(N, next_dir), 0.0) / PI;
    float pdf_spec_base = pdf_GGX_for_direction(N, V, next_dir, eff_roughness);
    float pdf_spec_cc = 0.0;
    if (payload.clearcoat > 0.0) {
        pdf_spec_cc = pdf_GGX_for_direction(N, V, next_dir, eff_clearcoat_roughness);
    }

    float pdf_total = p_clearcoat * pdf_spec_cc + p_base * (q_spec_base * pdf_spec_base + q_diff_base * pdf_diff);

    // if direction goes below horizon, continue/break
    float cos_theta = dot(N, next_dir);
    if (cos_theta <= 0.0) break;

    // evaluate brdf and update throughput
    // Check if multi-layer material (blend_factor > 0 means multi-layer is active)
    float3 brdf;
    if (payload.blend_factor > 0.0) {
        // Use multi-layer material BRDF
        brdf = eval_brdf_multi_layer(
            N, next_dir, V,
            payload.albedo, eff_roughness, payload.metallic,
            payload.ao, payload.clearcoat, eff_clearcoat_roughness,
            payload.albedo_layer2, eff_roughness_layer2, payload.metallic_layer2,
            payload.ao_layer2, payload.clearcoat_layer2, eff_clearcoat_roughness_layer2,
            payload.thin, payload.blend_factor, payload.layer_thickness,
            payload.alpha_layer2  // Use alpha from texture for transparency
        );
    } else {
        // Use single-layer material BRDF (backward compatible)
        brdf = eval_brdf(N, next_dir, V, payload.albedo, eff_roughness, payload.metallic, payload.ao, payload.clearcoat, eff_clearcoat_roughness);
    }

    // This part remains the same, we do not change the coeff.
    throughput *= brdf * cos_theta / max(eps, pdf_total);

    // update ray for next bounce
    // Use geometric normal for offset to prevent self-intersection with normal maps
    float3 offset_dir = dot(next_dir, payload.geometric_normal) > 0 ? payload.geometric_normal : -payload.geometric_normal;
    ray.Origin = payload.position + offset_dir * 1e-4;
    ray.Direction = next_dir;

    // ========================================================================
    // Firefly Reduction: Improved Russian Roulette Termination (Scheme 6)
    // ========================================================================
    // Russian roulette termination
    float p = saturate(max(throughput.x, max(throughput.y, throughput.z)));
    // Keep more indirect bounces alive: raise survival floor and soften cap
    p = clamp(p, 0.10, 0.99);
    
    // Force termination if throughput is too large (prevents fireflies)
    if (any(throughput > float3(1e4, 1e4, 1e4))) {
      break; // Force termination to prevent firefly
    }
    
    if (rand(rng_state) > p) break;
    throughput /= p;
    depth += 1;

    payload.rng_state = rng_state;
  }
  // Write outputs
  // Apply exposure then ACES tone mapping, followed by gamma for display
  float3 mapped_radiance = ACESFilm(radiance * render_settings.exposure);
  mapped_radiance = pow(mapped_radiance, 1.0 / 2.2);
  output[pixel_coords] = float4(mapped_radiance, 1.0);

  accumulated_color[pixel_coords] = accumulated_color[pixel_coords] + float4(radiance, 1.0);
  accumulated_samples[pixel_coords] = frame_count + 1;

}

// ============================================================================
// 包含其他 Shader 入口点
// ============================================================================

#include "miss.hlsl"
#include "closesthit.hlsl"

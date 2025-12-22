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
  
  while (true) { // infinite loop, we use RR to break :)

    // we trace a ray
    payload.hit = false;
    TraceRay(as, RAY_FLAG_NONE, 0xFF, 0, 1, 0, ray, payload);

    rng_state = payload.rng_state; 
    // TraceRay -> ClosestHitMain -> EvaluateLight -> rand -> rand_xorshift changes rng_state

    // record the id of this entity, if hit
    if (depth == 0) {
      entity_id_output[pixel_coords] = payload.hit ? (int)payload.instance_id : -1;
    }

    // if not hit, accumulate sky color and break
    if (!payload.hit) {
      // gradient sky 
      // float t = 0.5 * (normalize(ray.Direction).y + 1.0);
      // float3 sky_color = lerp(float3(1.0, 1.0, 1.0), float3(0.5, 0.7, 1.0), t);
      // radiance += throughput * sky_color;
      break;
    }

    radiance += throughput * payload.emission; // emissive term
    radiance += throughput * payload.direct_light; // direct lighting

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
    float3 h_local = sample_GGX_half(r4, r5, payload.roughness);
    float3 H_base = h_local.x * tangent + h_local.y * bitangent + h_local.z * N;
    H_base = normalize(H_base);
    float3 L_spec_base = normalize(reflect(-V, H_base));

    // Clearcoat Specular candidate
    float r6 = rand(rng_state);
    float r7 = rand(rng_state);
    float3 h_local_cc = sample_GGX_half(r6, r7, payload.clearcoat_roughness);
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
    float pdf_spec_base = pdf_GGX_for_direction(N, V, next_dir, payload.roughness);
    float pdf_spec_cc = 0.0;
    if (payload.clearcoat > 0.0) {
        pdf_spec_cc = pdf_GGX_for_direction(N, V, next_dir, payload.clearcoat_roughness);
    }

    float pdf_total = p_clearcoat * pdf_spec_cc + p_base * (q_spec_base * pdf_spec_base + q_diff_base * pdf_diff);

    // if direction goes below horizon, continue/break
    float cos_theta = dot(N, next_dir);
    if (cos_theta <= 0.0) break;

    // evaluate brdf and update throughput
    float3 brdf = eval_brdf(N, next_dir, V, payload.albedo, payload.roughness, payload.metallic, payload.ao, payload.clearcoat, payload.clearcoat_roughness);

    // This part remains the same, we do not change the coeff.
    throughput *= brdf * cos_theta / max(eps, pdf_total);

    // update ray for next bounce
    ray.Origin = payload.position + next_dir * payload.new_eps;  // offset a bit to avoid self-intersection!!!!
    ray.Direction = next_dir;

    // Russian roulette termination
    float p = saturate(max(throughput.x, max(throughput.y, throughput.z)));
    p = clamp(p, 0.05, 0.95);
    if (rand(rng_state) > p) break;
    throughput /= p;
    depth += 1;

    payload.rng_state = rng_state;
  }
  // Write outputs
  output[pixel_coords] = float4(radiance, 1.0);

  accumulated_color[pixel_coords] = accumulated_color[pixel_coords] + float4(radiance, 1.0);
  accumulated_samples[pixel_coords] = frame_count + 1;

}

// ============================================================================
// 包含其他 Shader 入口点
// ============================================================================

#include "miss.hlsl"
#include "closesthit.hlsl"

struct CameraInfo {
  float4x4 screen_to_camera;
  float4x4 camera_to_world;
};

struct Material {
  float4 base_color_factor;
  int base_color_tex;

  float roughness_factor;
  float metallic_factor;
  int metallic_roughness_tex;

  float3 emissive_factor;
  int emissive_texture;
  
  float AO_strength;
  int AO_texture;

  float normal_scale;
  int normal_texture;

  float clearcoat_factor;
  float clearcoat_roughness_factor;

  int alpha_mode; // 0: OPAQUE, 1: MASK, 2: BLEND

  float transmission;
  float ior;

  float dispersion;
};

struct HoverInfo {
  int hovered_entity_id;
  int light_count;
};

struct Light {
  int type;
  float3 color;
  float intensity;

  float3 position;
  float3 direction;
  float3 u;
  float3 v;
};

struct Vertex {
  float3 position;
};

RaytracingAccelerationStructure as : register(t0, space0);
RWTexture2D<float4> output : register(u0, space1);
ConstantBuffer<CameraInfo> camera_info : register(b0, space2);
StructuredBuffer<Material> materials : register(t0, space3);
ConstantBuffer<HoverInfo> hover_info : register(b0, space4);
RWTexture2D<int> entity_id_output : register(u0, space5);
RWTexture2D<float4> accumulated_color : register(u0, space6);
RWTexture2D<int> accumulated_samples : register(u0, space7);
StructuredBuffer<Vertex> Vertices[] : register(t0, space8);
StructuredBuffer<int> Indices[]     : register(t0, space9);
StructuredBuffer<float2> Texcoords[] : register(t0, space10);
Texture2D<float4> Textures[] : register(t0, space11);
SamplerState LinearWrap : register(s0, space12);
StructuredBuffer<float3> Normals[] : register(t0, space13);
StructuredBuffer<float3> Tangents[] : register(t0, space14);
StructuredBuffer<Light> Lights : register(t0, space15);

// Now we compute color in RayGenMain
// So I define RayPayload accordingly
struct RayPayload {
  bool hit;
  uint instance_id;

  float3 position;
  float3 normal;

  float3 albedo;

  float roughness;
  float metallic;

  float3 emission;

  float ao;

  float clearcoat;
  float clearcoat_roughness;

  float transmission;
  float ior;

  float dispersion;

  int alpha_mode;
  float alpha;

  float new_eps;
  bool front_face;
  
  // Light contribution
  float3 direct_light;

  uint rng_state;
};

static const float PI = 3.14159265359;
static const float eps = 1e-6;

// We need rand variables for Monte Carlo integration
// I leverage a simple Wang Hash + Xorshift RNG combo here
uint wang_hash(uint seed) {
  seed = (seed ^ 61) ^ (seed >> 16);
  seed *= 9;
  seed = seed ^ (seed >> 4);
  seed *= 0x27d4eb2;
  seed = seed ^ (seed >> 15);
  return seed;
}

uint rand_xorshift(inout uint rng_state) {
  rng_state ^= rng_state << 13;
  rng_state ^= rng_state >> 17;
  rng_state ^= rng_state << 5;
  return rng_state;
}

float rand(inout uint rng_state) {
  return float(rand_xorshift(rng_state)) * (1.0 / 4294967296.0);
} //rand will change rng_state

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


bool dead();

bool CastShadowRay(float3 origin, float3 direction, float max_distance) {
    RayDesc shadow_ray;
    shadow_ray.Origin = origin;
    shadow_ray.Direction = direction;
    shadow_ray.TMin = eps;
    shadow_ray.TMax = max_distance;

    // [Fix] Use RayPayload to match the signature of MissMain
    RayPayload shadow_payload;
    shadow_payload.hit = true;
    TraceRay(
        as, 
        RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH | RAY_FLAG_SKIP_CLOSEST_HIT_SHADER, 
        0xFF, 
        0,
        1, 
        0,
        shadow_ray, 
        shadow_payload
    );
    
    return shadow_payload.hit;
}//1= hit

bool dead() {
  int i = 2;
  while (i >= 0) {
    if (i == 2) i -= 2;
    else i += 2;
  }
  return true;
}

float3 eval_brdf(float3 N, float3 L, float3 V, float3 albedo, float roughness, float metallic, float ao, float clearcoat, float clearcoat_roughness);

float3 EvaluateLight(Light light, float3 position, float3 normal, float3 view_dir, float3 albedo, float roughness, float metallic, float ao, float clearcoat, float clearcoat_roughness, inout uint rng_state) {
  float3 direct_light = float3(0.0, 0.0, 0.0);
  
  // POINT_LIGHT
  float3 light_dir;
  float3 radiance;
  float inv_pdf;
  float max_distance;
  if (light.type == 0) {
    radiance = SamplePointLight(light, position, light_dir, inv_pdf);
    max_distance = length(light.position - position);
  } else if (light.type == 1) {
    float3 sampled_point;
    radiance = SampleAreaLight(light, position, light_dir, inv_pdf, sampled_point, rng_state);
    max_distance = length(sampled_point - position);
  }
  float NdotL = max(dot(normal, light_dir), 0.0);
  if (NdotL > 0.0) {
    // [Fix] Clamp roughness for NEE to reduce fireflies on smooth surfaces
    float safe_roughness = max(roughness, 0.15);
    float3 brdf = eval_brdf(normal, light_dir, view_dir, albedo, safe_roughness, metallic, ao, clearcoat, clearcoat_roughness);
    if (!CastShadowRay(position + normal * 1e-3, light_dir, max_distance - 1e-3)) {
      direct_light = brdf * radiance * NdotL * inv_pdf;
    }
  }
  return direct_light;
}

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

[shader("miss")] void MissMain(inout RayPayload payload) {
  payload.hit = false;
}

[shader("closesthit")] void ClosestHitMain(inout RayPayload payload, in BuiltInTriangleIntersectionAttributes attr) {
  payload.hit = true;
  
  // Get material index from instance
  uint material_idx = InstanceID();
  payload.instance_id = material_idx;
  
  // Load material
  Material mat = materials[material_idx];
  
  // Get vertex from geometry
  uint primitiveID = PrimitiveIndex();
  int index0 = Indices[material_idx][primitiveID * 3 + 0];
  int index1 = Indices[material_idx][primitiveID * 3 + 1];
  int index2 = Indices[material_idx][primitiveID * 3 + 2];

  Vertex v0 = Vertices[material_idx][index0];
  Vertex v1 = Vertices[material_idx][index1];
  Vertex v2 = Vertices[material_idx][index2];

  // Use uv to get texcoords
  float2 uv0 = Texcoords[material_idx][index0];
  float2 uv1 = Texcoords[material_idx][index1];
  float2 uv2 = Texcoords[material_idx][index2];

  float2 bc = attr.barycentrics;
  float3 bary = float3(1.0 - bc.x - bc.y, bc.x, bc.y);
  float2 uv = uv0 * bary.x + uv1 * bary.y + uv2 * bary.z;

  float3 base_color_tex = (mat.base_color_tex >= 0) ? Textures[mat.base_color_tex].SampleLevel(LinearWrap, uv, 0.0f).rgb : float3(1.0f, 1.0f, 1.0f);
  float alpha_tex = (mat.base_color_tex >= 0) ? Textures[mat.base_color_tex].SampleLevel(LinearWrap, uv, 0.0f).a : 1.0f;
  float metallic_roughness_tex = (mat.metallic_roughness_tex >= 0) ? Textures[mat.metallic_roughness_tex].SampleLevel(LinearWrap, uv, 0.0f).b : 1.0f;
  float roughness_tex = (mat.metallic_roughness_tex >= 0) ? Textures[mat.metallic_roughness_tex].SampleLevel(LinearWrap, uv, 0.0f).g : 1.0f;
  float3 emissive_tex = (mat.emissive_texture >= 0) ? Textures[mat.emissive_texture].SampleLevel(LinearWrap, uv, 0.0f).rgb : float3(1.0f, 1.0f, 1.0f);
  float AO_tex = (mat.AO_texture >= 0) ? Textures[mat.AO_texture].SampleLevel(LinearWrap, uv, 0.0f).r : 1.0f;

  float3 base_color = mat.base_color_factor.rgb * base_color_tex;
  float alpha = mat.base_color_factor.a * alpha_tex;
  float metallic = mat.metallic_factor * metallic_roughness_tex;
  float roughness = max(0.1f, mat.roughness_factor * roughness_tex);
  float3 emission = mat.emissive_factor * emissive_tex;
  float AO = 1.0 + (AO_tex - 1.0) * mat.AO_strength;

  // Compute normal
  float3 n0 = Normals[material_idx][index0];
  float3 n1 = Normals[material_idx][index1];
  float3 n2 = Normals[material_idx][index2];

  float3 normal = float3(0.0, 0.0, 0.0);
  if (length(n0) < 0.001 || length(n1) < 0.001 || length(n2) < 0.001) {
    // use geometric normal
    float3 edge1 = v1.position - v0.position;
    float3 edge2 = v2.position - v0.position;
    normal = normalize(cross(edge1, edge2));
  } else {
    // use interpolated normal
    float2 bc = attr.barycentrics;
    float3 bary = float3(1.0 - bc.x - bc.y, bc.x, bc.y);
    normal = n0 * bary.x + n1 * bary.y + n2 * bary.z;
    normal = normalize(normal);
  }

  float3 world_normal = normalize(mul(ObjectToWorld3x4(), float4(normal, 0.0)));

  payload.front_face = true;
  if (dot(world_normal, WorldRayDirection()) > 0.0) {
    world_normal = -world_normal;
    payload.front_face = false;
  }

  if (mat.normal_texture >= 0) {
    float3 tangent = normalize(Tangents[material_idx][index0] * bary.x +
                     Tangents[material_idx][index1] * bary.y +
                     Tangents[material_idx][index2] * bary.z);

    float3 world_tangent = normalize(mul((float3x3)ObjectToWorld3x4(), tangent));

    world_tangent = normalize(world_tangent - dot(world_tangent, world_normal) * world_normal);

    float3 world_bitangent = normalize(cross(world_normal, world_tangent));

    float3 normal_map_sample = Textures[mat.normal_texture].SampleLevel(LinearWrap, uv, 0.0f).rgb;
    normal_map_sample = normal_map_sample * 2.0 - 1.0;
    normal_map_sample.xy *= mat.normal_scale;

    // Transform normal from tangent space to world space
    world_normal = normalize(normal_map_sample.x * world_tangent + normal_map_sample.y * world_bitangent + normal_map_sample.z * world_normal);
  }

  payload.position = WorldRayOrigin() + WorldRayDirection() * RayTCurrent();
  payload.normal = world_normal;

  payload.albedo = base_color;

  payload.roughness = roughness;
  payload.metallic = metallic;

  payload.emission = emission;

  payload.ao = AO;

  payload.clearcoat = mat.clearcoat_factor;
  payload.clearcoat_roughness = mat.clearcoat_roughness_factor;

  payload.transmission = mat.transmission;
  payload.ior = mat.ior;
  payload.dispersion = mat.dispersion;
  payload.new_eps = RayTCurrent() * 1e-4 + eps;
  
  payload.alpha_mode = mat.alpha_mode;
  payload.alpha = alpha;
  
  // Calculate direct lighting
  payload.direct_light = float3(0.0, 0.0, 0.0);
  float3 view_dir = -normalize(WorldRayDirection());
  
  // Sample all lights
  for (uint i = 0; i < hover_info.light_count; ++i) {
    Light light = Lights[i];
    payload.direct_light += EvaluateLight(light, payload.position, payload.normal, view_dir, payload.albedo, payload.roughness, payload.metallic, payload.ao, payload.clearcoat, payload.clearcoat_roughness, payload.rng_state);
  }
}
struct CameraInfo {
  float4x4 screen_to_camera;
  float4x4 camera_to_world;
};

struct Material {
  float3 base_color;
  float roughness;
  float3 emission;
  float metallic;
  float transmission;
  float ior;
};

struct HoverInfo {
  int hovered_entity_id;
};

struct Vertex {
  float3 position;
};

struct LightTriangle {
    float3 v0; float pad0;
    float3 v1; float pad1;
    float3 v2; float pad2;
    float3 emission; float pad3;
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
StructuredBuffer<LightTriangle> lights : register(t0, space10);

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
  
  float transmission;
  float ior;
  float front_face;
};

static const float PI = 3.14159265359;
static const float eps = 1e-5;

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
  return a2 / (PI * denom * denom);
}

float G_Smith(float NdotV, float NdotL, float roughness) {
  // G = G1(in) * G1(out), G11 = 2 * (n * v) / (n * v  + sqrt(a2 + (1 - a2) * (n * v)^2))
  float a = roughness * roughness;
  float a2 = a * a;
  float ggx1 = 2 * NdotV / (NdotV + sqrt(a2 + (1.0 - a2) * NdotV * NdotV));
  float ggx2 = 2 * NdotL / (NdotL + sqrt(a2 + (1.0 - a2) * NdotL * NdotL));
  return ggx1 * ggx2;
}

float3 eval_brdf(float3 N, float3 L, float3 V, float3 albedo, float roughness, float metallic) {
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

    float3 specular = (D * G * F) / (4.0 * NdotV * NdotL + eps);
    
    float3 kS = F;
    float3 kD = (1.0 - kS) * (1.0 - metallic);
    float3 diffuse = kD * albedo / PI;

    return diffuse + specular;
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
  return (D * NdotH) / (4.0 * VdotH + eps);
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
  float t_max = 10000.0;
  RayDesc ray;
  ray.Origin = origin.xyz;
  ray.Direction = normalize(direction.xyz);
  ray.TMin = t_min;
  ray.TMax = t_max;

  RayPayload payload;
  float3 throughput = float3(1.0, 1.0, 1.0);
  float3 radiance = float3(0.0, 0.0, 0.0);

  // core of path tracing

  int depth = 0;
  
  while (true) { // infinite loop, we use RR to break :)

    // we trace a ray
    payload.hit = false;
    TraceRay(as, RAY_FLAG_NONE, 0xFF, 0, 1, 0, ray, payload);

    // record the id of this entity, if hit
    if (depth == 0) {
      entity_id_output[pixel_coords] = payload.hit ? (int)payload.instance_id : -1;
    }

    // if not hit, accumulate sky color and break
    if (!payload.hit) {
      // gradient sky 
      float t = 0.5 * (normalize(ray.Direction).y + 1.0);
      float3 sky_color = lerp(float3(1.0, 1.0, 1.0), float3(0.5, 0.7, 1.0), t);
      radiance += throughput * sky_color;
      break;
    }

    radiance += throughput * payload.emission; // emissive term

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
        float F = F_Schlick(float3(F0, F0, F0), dot(V, N)).x;
        
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
            ray.Origin = payload.position - N * eps; // rem offset
            ray.Direction = normalize(refract_dir);
            throughput *= payload.albedo; // you get albedo tint on refraction
        }
        
        // weighting
        throughput /= payload.transmission;
        
        float p = max(0.95, saturate(max(throughput.x, max(throughput.y, throughput.z))));
        if (rand(rng_state) > p) break;
        throughput /= p;
        depth += 1;
        
        continue; // skip opaque, so if transmission chosen, it's not metallic, rough, etc.
      } else {
        // Normalize throughput for not choosing transmission
        throughput /= (1.0 - payload.transmission);
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

    // diffuse candidate
    float3 local_diff = sample_cosine_hemisphere(r1, r2);
    float3 L_diff = local_diff.x * tangent + local_diff.y * bitangent + local_diff.z * N;
    L_diff = normalize(L_diff);
    // pdf = cos / pi
    float pdf_diff_at_Ldiff = max(dot(N, L_diff), 0.0) / PI;

    // specular candidate
    float r4 = rand(rng_state);
    float r5 = rand(rng_state);
    float3 h_local = sample_GGX_half(r4, r5, payload.roughness);
    float3 H = h_local.x * tangent + h_local.y * bitangent + h_local.z * N;
    H = normalize(H);
    float3 L_spec = normalize(reflect(-V, H));
    // calc pdf
    float pdf_spec_at_Lspec = pdf_GGX_for_direction(N, V, L_spec, payload.roughness);

    // choose which direction to actually trace
    // use F to decide q
    float3 F0 = lerp(float3(0.04, 0.04, 0.04), payload.albedo, payload.metallic);
    float3 F = F_Schlick(F0, dot(N, V));
    float luminance = dot(F, float3(0.2126, 0.7152, 0.0722));
    float q_spec = clamp(saturate(luminance), 0.05, 0.95);
    float q_diff = 1.0 - q_spec;

    float3 next_dir;
    if (r3 < q_spec) {
      next_dir = L_spec;
    } else {
      next_dir = L_diff;
    }

    // in order to do MIS, we need to compute the pdf both startegies
    float pdf_diff_at_sel = max(dot(N, next_dir), 0.0) / PI;
    float pdf_spec_at_sel = pdf_GGX_for_direction(N, V, next_dir, payload.roughness);

    // combined pdf for MIS
    float pdf_total = q_diff * pdf_diff_at_sel + q_spec * pdf_spec_at_sel;
    pdf_total = max(pdf_total, eps);

    // if direction goes below horizon, continue/break
    float cos_theta = dot(N, next_dir);
    if (cos_theta <= 0.0) break;

    // evaluate brdf and update throughput
    float3 brdf = eval_brdf(N, next_dir, V, payload.albedo, payload.roughness, payload.metallic);

    // This part remains the same, we do not change the coeff.
    throughput *= brdf * cos_theta / pdf_total;

    // update ray for next bounce
    ray.Origin = payload.position + N * eps;  // offset a bit to avoid self-intersection!!!!
    ray.Direction = next_dir;

    // Russian roulette termination
    float p = max(0.95, saturate(max(throughput.x, max(throughput.y, throughput.z))));
    if (rand(rng_state) > p) break;
    throughput /= p;
    depth += 1;
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

  // Calculate normal
  float3 edge1 = v1.position - v0.position;
  float3 edge2 = v2.position - v0.position;
  float3 normal = normalize(cross(edge1, edge2));

  float3 world_normal = normalize(mul(ObjectToWorld3x4(), float4(normal, 0.0)));

  payload.front_face = true;
  if (dot(world_normal, WorldRayDirection()) > 0.0) {
    world_normal = -world_normal;
    payload.front_face = false;
  }

  payload.position = WorldRayOrigin() + WorldRayDirection() * RayTCurrent();
  payload.normal = world_normal;
  payload.albedo = (float3)mat.base_color;
  payload.roughness = mat.roughness;
  payload.metallic = mat.metallic;
  payload.emission = (float3)mat.emission;
  payload.transmission = mat.transmission;
  payload.ior = mat.ior;
}
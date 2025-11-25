
struct CameraInfo {
  float4x4 screen_to_camera;
  float4x4 camera_to_world;
};

struct Material {
  float3 base_color;
  float roughness;
  float metallic;
};

struct HoverInfo {
  int hovered_entity_id;
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
};

static const float PI = 3.14159265359;
static const int MAX_DEPTH = 5;

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


[shader("raygeneration")] void RayGenMain() {
  // Path tracing implementation is now deprecated
  // I prefer to keep the code :)
  // float2 pixel_center = (float2)DispatchRaysIndex() + float2(0.5, 0.5);
  // float2 uv = pixel_center / float2(DispatchRaysDimensions().xy);
  // uv.y = 1.0 - uv.y;
  // float2 d = uv * 2.0 - 1.0;
  // float4 origin = mul(camera_info.camera_to_world, float4(0, 0, 0, 1));
  // float4 target = mul(camera_info.screen_to_camera, float4(d, 1, 1));
  // float4 direction = mul(camera_info.camera_to_world, float4(target.xyz, 0));

  // float t_min = 0.001;
  // float t_max = 10000.0;

  // RayPayload payload;
  // payload.color = float3(0, 0, 0);
  // payload.hit = false;
  // payload.instance_id = 0;

  // RayDesc ray;
  // ray.Origin = origin.xyz;
  // ray.Direction = normalize(direction.xyz);
  // ray.TMin = t_min;
  // ray.TMax = t_max;

  // TraceRay(as, RAY_FLAG_NONE, 0xFF, 0, 1, 0, ray, payload);

  // uint2 pixel_coords = DispatchRaysIndex().xy;
  
  // // Write to immediate output (for camera movement mode)
  // output[pixel_coords] = float4(payload.color, 1);
  
  // // Write entity ID to the ID buffer
  // // If no hit, write -1; otherwise write the instance ID
  // entity_id_output[pixel_coords] = payload.hit ? (int)payload.instance_id : -1;
  
  // // Accumulate color for progressive rendering (when camera is stationary)
  // float4 prev_color = accumulated_color[pixel_coords];
  // int prev_samples = accumulated_samples[pixel_coords];
  
  // accumulated_color[pixel_coords] = prev_color + float4(payload.color, 1);
  // accumulated_samples[pixel_coords] = prev_samples + 1;

  uint2 pixel_coords = DispatchRaysIndex().xy;
  int frame_count = accumulated_samples[pixel_coords];

  // we hash the state with both pixel coordinates and frame count
  uint rng_state = wang_hash((pixel_coords.x + pixel_coords.y * DispatchRaysDimensions().x) + 1919810) ^ wang_hash(frame_count + 114514);

  // The calculating uv, d, origin, target and direction part remains the same
  float2 pixel_center = (float2)DispatchRaysIndex() + float2(0.5, 0.5);
  float2 uv = pixel_center / float2(DispatchRaysDimensions().xy);
  uv.y = 1.0 - uv.y;
  float2 d = uv * 2.0 - 1.0;
  float4 origin = mul(camera_info.camera_to_world, float4(0, 0, 0, 1));
  float4 target = mul(camera_info.screen_to_camera, float4(d, 1, 1));
  float4 direction = mul(camera_info.camera_to_world, float4(target.xyz, 0));

  // The ray init part remains the same
  float t_min = 0.001;
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
  for (int depth = 0; depth < MAX_DEPTH; ++depth) {

    // we trace a ray
    payload.hit = false;
    TraceRay(as, RAY_FLAG_NONE, 0xFF, 0, 1, 0, ray, payload);

    // record the id of this entity, if hit
    if (depth == 0) {
      entity_id_output[pixel_coords] = payload.hit ? (int)payload.instance_id : -1;
    }

    // if not hit, accumulate sky color and break
    if (!payload.hit) {
      float t = 0.5 * (normalize(ray.Direction).y + 1.0);
      float3 sky_color = lerp(float3(1.0, 1.0, 1.0), float3(0.5, 0.7, 1.0), t);
      radiance += throughput * sky_color;
      break;
    }

    // otherwise, prepare the next bounce, N is the normal
    float3 N = payload.normal;

    // Sample a cosine-weighted hemisphere direction around N
    // ratio1, ratio2 in [0, 1)
    // decide angle phi = (2pi * ratio1)
    // decide radius in xy plane = sqrt(ratio2)
    // decide height z = sqrt(1 - ratio2)
    float r1 = rand(rng_state);
    float r2 = rand(rng_state);
    float phi = 2.0 * PI * r1;
    float sqrt_r2 = sqrt(r2);
    float3 local_dir = float3(cos(phi) * sqrt_r2, sin(phi) * sqrt_r2, sqrt(1.0 - r2));

    // here, (tan, bitan, up) is an orthogonal basis
    float3 up = abs(N.z) < 0.999 ? float3(0, 0, 1) : float3(1, 0, 0);
    float3 tangent = normalize(cross(up, N));
    float3 bitangent = cross(N, tangent);
    float3 next_dir = local_dir.x * tangent + local_dir.y * bitangent + local_dir.z * N;

    // Lambertian : throughtput *= albedo
    throughput *= payload.albedo;

    // update ray for next bounce
    ray.Origin = payload.position + N * 0.001;  // offset a bit to avoid self-intersection!!!!
    ray.Direction = normalize(next_dir);

    // Russian roulette termination
    if (depth > 2) {
      float p = max(throughput.r, max(throughput.g, throughput.b));
      if (rand(rng_state) > p) {
        break;
      }
    }
  }
  
  // Write outputs ( I forgot to do this at first :( )
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

  if (dot(world_normal, WorldRayDirection()) > 0.0) {
    world_normal = -world_normal;
  }

  payload.position = WorldRayOrigin() + WorldRayDirection() * RayTCurrent();
  payload.normal = world_normal;
  payload.albedo = mat.base_color;
  payload.roughness = mat.roughness;
  payload.metallic = mat.metallic;
}

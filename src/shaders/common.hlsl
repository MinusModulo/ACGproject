// ============================================================================
// Common.hlsl - 数据结构定义和资源绑定
// ============================================================================

#ifndef COMMON_HLSL
#define COMMON_HLSL

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

// Constants
static const float PI = 3.14159265359;
static const float eps = 1e-6;

// Resource bindings
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

#endif // COMMON_HLSL


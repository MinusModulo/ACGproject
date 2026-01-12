// ============================================================================
// Common.hlsl - 数据结构定义和资源绑定
// ============================================================================

#ifndef COMMON_HLSL
#define COMMON_HLSL

struct CameraInfo {
  float4x4 screen_to_camera;
  float4x4 camera_to_world;
  float aperture;
  float focus_distance;
  float2 pad_camera;
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

  // ============================================================================
  // Multi-Layer Material: Layer 2 (Outer Layer) Properties
  // ============================================================================
  
  // Layer 2 Base Color
  float4 base_color_factor_layer2;
  int base_color_tex_layer2;

  // Layer 2 Roughness, Metallic
  float roughness_factor_layer2;
  float metallic_factor_layer2;
  int metallic_roughness_tex_layer2;

  // Layer 2 Emission
  float3 emissive_factor_layer2;
  int emissive_texture_layer2;

  // Layer 2 Occlusion
  float AO_strength_layer2;
  int AO_texture_layer2;

  // Layer 2 Normal
  float normal_scale_layer2;
  int normal_texture_layer2;

  // Layer 2 Clearcoat
  float clearcoat_factor_layer2;
  float clearcoat_roughness_factor_layer2;

  // Layer 2 alphaMode
  int alpha_mode_layer2;
  
  // Layer 2 Transmission, IOR
  float transmission_layer2;
  float ior_layer2;
  float dispersion_layer2;

  // Multi-Layer Material Control Parameters
  float thin;              // 0.0 = 厚层（不透明层），1.0 = 薄层（透明层）
  float blend_factor;      // 0.0-1.0，控制两层材质的混合强度
  float layer_thickness;   // 层厚度（用于薄层的光学计算）
};

struct HoverInfo {
  int hovered_entity_id;
  int light_count;
};

struct VolumeRegion {
    float3 min_p;
    float pad0;
    float3 max_p;
    float sigma_t;
    float3 sigma_s;
    float pad1;
};

struct SkyInfo {
  int use_skybox;
  float env_intensity;
  float bg_intensity;
  float pad_sky;
};

struct RenderSettings {
  int max_bounces;
  float exposure;
  float2 pad_render;
};

struct Light {
  int type;
  float3 color;
  float intensity;
  float angular_radius; // half-angle in radians for sun lights

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
  float3 geometric_normal;

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

  // ============================================================================
  // Multi-Layer Material: Layer 2 Properties
  // ============================================================================
  
  // Layer 2 material properties
  float3 albedo_layer2;
  float roughness_layer2;
  float metallic_layer2;
  float3 emission_layer2;
  float ao_layer2;
  float clearcoat_layer2;
  float clearcoat_roughness_layer2;
  float transmission_layer2;
  float ior_layer2;
  float dispersion_layer2;
  int alpha_mode_layer2;
  float alpha_layer2;

  // Multi-Layer Material Control
  float thin;
  float blend_factor;
  float layer_thickness;
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
Texture2D<float4> SkyboxTexture : register(t0, space16);
ConstantBuffer<VolumeRegion> volume_info : register(b0, space17);
ConstantBuffer<SkyInfo> sky_info : register(b0, space18);
ConstantBuffer<RenderSettings> render_settings : register(b0, space19);

#endif // COMMON_HLSL


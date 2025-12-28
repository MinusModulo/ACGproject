// ============================================================================
// Miss.hlsl - Miss Shader 模块
// ============================================================================

#include "common.hlsl"

float2 DirectionToEquirectangularUV(float3 direction) {
    float u = atan2(direction.z, direction.x) / (2.0 * PI) + 0.5;
    float v = 0.5 - asin(direction.y) / PI;
    return float2(u, v);
}

[shader("miss")] void MissMain(inout RayPayload payload) {
  payload.hit = false;
  float3 ray_dir = normalize(WorldRayDirection());
  float2 uv = DirectionToEquirectangularUV(ray_dir);
  float3 sky_color = (sky_info.use_skybox != 0)
    ? SkyboxTexture.SampleLevel(LinearWrap, uv, 0).rgb
    : float3(0.0, 0.0, 0.0);
  payload.emission = sky_color;
}


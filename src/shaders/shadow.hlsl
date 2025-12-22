// ============================================================================
// Shadow.hlsl - 阴影检测模块
// ============================================================================

#ifndef SHADOW_HLSL
#define SHADOW_HLSL

#include "common.hlsl"

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

#endif // SHADOW_HLSL


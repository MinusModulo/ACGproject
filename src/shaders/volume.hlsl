#ifndef VOLUME_HLSL
#define VOLUME_HLSL

#include "common.hlsl"
#include "sampling.hlsl"
#include "rng.hlsl"

// Ray-AABB intersection
bool IntersectAABB(RayDesc ray, float3 min_p, float3 max_p, out float t_enter, out float t_exit) {
    float3 inv_d = 1.0 / ray.Direction;
    float3 t0 = (min_p - ray.Origin) * inv_d;
    float3 t1 = (max_p - ray.Origin) * inv_d;
    
    float3 t_small = min(t0, t1);
    float3 t_big = max(t0, t1);
    
    t_enter = max(max(t_small.x, t_small.y), t_small.z);
    t_exit = min(min(t_big.x, t_big.y), t_big.z);
    
    return t_enter < t_exit && t_exit > 0.0;
}

// Sample homogeneous volume
// Returns true if scattering happened, false otherwise
bool SampleHomogeneousVolume(
    inout RayDesc ray, 
    inout float3 throughput, 
    inout uint rng_state, 
    VolumeRegion vol, 
    float hit_dist
) {
    float t_enter, t_exit;
    
    // 1. Check intersection with volume bounds
    if (!IntersectAABB(ray, vol.min_p, vol.max_p, t_enter, t_exit)) {
        return false;
    }
    
    // 2. Clip intersection to the ray segment [0, hit_dist]
    t_enter = max(t_enter, 0.0);
    t_exit = min(t_exit, hit_dist);
    
    // If the segment is invalid or empty, no volume interaction
    if (t_enter >= t_exit) return false;
    
    // 3. Sample scattering distance
    float dist_in_volume = t_exit - t_enter;
    float dist_sample = -log(rand(rng_state)) / vol.sigma_t;
    
    // 4. Check if scattering happens within the volume segment
    if (dist_sample < dist_in_volume) {
        // Scattering event
        ray.Origin = ray.Origin + ray.Direction * (t_enter + dist_sample);
        ray.Direction = sample_uniform_sphere(rand(rng_state), rand(rng_state));
        throughput *= (vol.sigma_s / vol.sigma_t);
        return true;
    }
    
    // No scattering, ray passes through (transmittance is handled by importance sampling)
    return false;
}

#endif // VOLUME_HLSL

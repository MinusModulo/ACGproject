#ifndef VOLUME_HLSL
#define VOLUME_HLSL

#include "common.hlsl"
#include "sampling.hlsl"
#include "rng.hlsl"

// Ray-AABB intersection with safe division for zero direction components
bool IntersectAABB(RayDesc ray, float3 min_p, float3 max_p, out float t_enter, out float t_exit) {
    float3 inv_d = float3(
        ray.Direction.x != 0.0 ? 1.0 / ray.Direction.x : 1e6,
        ray.Direction.y != 0.0 ? 1.0 / ray.Direction.y : 1e6,
        ray.Direction.z != 0.0 ? 1.0 / ray.Direction.z : 1e6
    );

    float3 t0 = (min_p - ray.Origin) * inv_d;
    float3 t1 = (max_p - ray.Origin) * inv_d;
    
    float3 t_small = min(t0, t1);
    float3 t_big = max(t0, t1);
    
    t_enter = max(max(t_small.x, t_small.y), t_small.z);
    t_exit = min(min(t_big.x, t_big.y), t_big.z);
    
    return (t_enter <= t_exit) && (t_exit > ray.TMin);
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
    // Skip when extinction is not positive
    if (vol.sigma_t <= 0.0) {
        return false;
    }

    float t_enter, t_exit;
    
    // 1. Check intersection with volume bounds
    if (!IntersectAABB(ray, vol.min_p, vol.max_p, t_enter, t_exit)) {
        return false;
    }
    
    // 2. Clip intersection to the ray segment [TMin, hit_dist]
    t_enter = max(t_enter, ray.TMin);
    t_exit = min(t_exit, hit_dist);
    
    // If the segment is invalid or empty, no volume interaction
    if (t_enter >= t_exit) {
        return false;
    }
    
    // 3. Sample scattering distance from exponential distribution
    float segment_length = t_exit - t_enter;
    float u = max(1e-6, 1.0 - rand(rng_state));
    float dist_sample = -log(u) / vol.sigma_t;

    float3 sigma_t_vec = float3(vol.sigma_t, vol.sigma_t, vol.sigma_t);
    float3 albedo = vol.sigma_s / max(vol.sigma_t, 1e-6);
    
    if (dist_sample < segment_length) {
        // Scattering event inside the medium
        float3 trans = exp(-sigma_t_vec * dist_sample);
        throughput *= trans * albedo;
        ray.Origin = ray.Origin + ray.Direction * (t_enter + dist_sample);
        ray.Direction = sample_uniform_sphere(rand(rng_state), rand(rng_state));
        ray.TMin = 1e-3;
        return true;
    }
    
    // No scattering before exiting the volume; apply transmittance for the full segment
    float3 trans_exit = exp(-sigma_t_vec * segment_length);
    throughput *= trans_exit;
    return false;
}

#endif // VOLUME_HLSL

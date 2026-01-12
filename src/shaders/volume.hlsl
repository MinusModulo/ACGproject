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

// Simple hash-based pseudo noise for density modulation
float Noise3(float3 p) {
    // Shift to reduce correlation when p has small integers
    p += float3(17.0, 59.4, 15.0);
    float n = dot(p, float3(12.9898, 78.233, 37.719));
    return frac(sin(n) * 43758.5453);
}

// Procedural density in [0, 1] inside the volume
float DensityAtPoint(float3 p, VolumeRegion vol) {
    float3 size = vol.max_p - vol.min_p;
    // Avoid division by zero if bounds degenerate
    size = max(size, float3(1e-3, 1e-3, 1e-3));
    float3 local = saturate((p - vol.min_p) / size);

    // Base gradient (denser near the ground, linearly decays along +Y)
    float base = 1.0 - local.z;
    base = lerp(0.05, 0.3, base); // keep a floor to avoid zero density aloft
    float wavy = lerp(0.6, 1.0, Noise3(p * 1.7));
    float stripes = 0.5 + 0.5 * sin(dot(p, float3(0.8, 1.3, 0.6)));
    return saturate(base * wavy * stripes);
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
        // PDF of this distance is sigma_t * exp(-sigma_t * dist)
        // Transmittance is exp(-sigma_t * dist)
        // Weight = (Trans * sigma_s) / PDF = sigma_s / sigma_t = albedo
        throughput *= albedo;
        ray.Origin = ray.Origin + ray.Direction * (t_enter + dist_sample);
        ray.Direction = sample_uniform_sphere(rand(rng_state), rand(rng_state));
        ray.TMin = 1e-3;
        return true;
    }
    
    // No scattering before exiting the volume
    // PDF of surviving is exp(-sigma_t * length)
    // Transmittance is exp(-sigma_t * length)
    // Weight = Trans / PDF = 1.0
    return false;
}

// Delta (ratio) tracking for inhomogeneous media using sigma_t as majorant
// Returns true if a real scattering event occurred, false otherwise
bool SampleInhomogeneousVolume(
    inout RayDesc ray,
    inout float3 throughput,
    inout uint rng_state,
    VolumeRegion vol,
    float hit_dist
) {
    float sigma_t_max = vol.sigma_t;
    if (sigma_t_max <= 0.0) {
        return false;
    }

    float t_enter, t_exit;
    if (!IntersectAABB(ray, vol.min_p, vol.max_p, t_enter, t_exit)) {
        return false;
    }

    t_enter = max(t_enter, ray.TMin);
    t_exit = min(t_exit, hit_dist);
    if (t_enter >= t_exit) {
        return false;
    }

    float3 albedo = vol.sigma_s / max(vol.sigma_t, 1e-6);
    float t = t_enter;
    const int max_steps = 1024; // Increased steps for safety

    for (int step = 0; step < max_steps; ++step) {
        // Sample free-flight distance using majorant
        float u = max(1e-6, 1.0 - rand(rng_state));
        float dist = -log(u) / sigma_t_max;

        t += dist;

        // If we exit before the next potential event, we made it through safely
        if (t >= t_exit) {
            return false;
        }

        float3 pos = ray.Origin + ray.Direction * t;
        float density = DensityAtPoint(pos, vol);
        float sigma_t_local = density * sigma_t_max;

        // Null-collision check
        // Probability of real collision: P = sigma_t_local / sigma_t_max
        if (rand(rng_state) < (sigma_t_local / sigma_t_max)) {
            // Real collision
            // Weight = albedo (same logic as homogeneous)
            throughput *= albedo;
            ray.Origin = pos;
            ray.Direction = sample_uniform_sphere(rand(rng_state), rand(rng_state));
            ray.TMin = 1e-3;
            return true;
        }
        // Else: Null collision, continue (weight * 1.0)
    }

    return false;
}

#endif // VOLUME_HLSL

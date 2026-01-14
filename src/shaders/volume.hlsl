#ifndef VOLUME_HLSL
#define VOLUME_HLSL

#include "common.hlsl"
#include "sampling.hlsl"
#include "rng.hlsl"
#include "light_sampling.hlsl"
#include "shadow.hlsl"

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

// Sample Henyey-Greenstein Phase Function
float3 sample_HG(float3 w, float g, float u1, float u2) {
    float cos_theta;
    if (abs(g) < 1e-3) {
        cos_theta = 1.0 - 2.0 * u1;
    } else {
        float sqr_term = (1.0 - g * g) / (1.0 - g + 2.0 * g * u1);
        cos_theta = (1.0 + g * g - sqr_term * sqr_term) / (2.0 * g);
    }
    
    float sin_theta = sqrt(max(0.0, 1.0 - cos_theta * cos_theta));
    float phi = 2.0 * PI * u2;
    
    float3 b1, b2;
    float3 n = w;
    if (abs(n.x) > 0.1) {
        b1 = normalize(cross(float3(0, 1, 0), n));
    } else {
        b1 = normalize(cross(float3(1, 0, 0), n));
    }
    b2 = cross(n, b1);
    
    return sin_theta * cos(phi) * b1 + sin_theta * sin(phi) * b2 + cos_theta * n;
}

float phase_HG(float cos_theta, float g) {
    float gg = g * g;
    float denom = pow(max(1.0 + gg - 2.0 * g * cos_theta, 1e-6), 1.5);
    return (1.0 - gg) / (4.0 * PI * denom);
}

float3 EvaluateVolumeDirectLighting(float3 position, float3 wo, float g, inout uint rng_state) {
    float3 Ld = 0.0;
    for (uint i = 0; i < hover_info.light_count; ++i) {
        Light light = Lights[i];

        float3 light_dir = 0.0;
        float3 radiance_light = 0.0;
        float inv_pdf = 1.0;
        float pdf = 1.0;
        float max_distance = 1e9;
        float3 sampled_point = 0.0;

        if (light.type == 0) {
            radiance_light = SamplePointLight(light, position, light_dir, inv_pdf);
            pdf = 1.0;
            max_distance = length(light.position - position);
        } else if (light.type == 2) {
            radiance_light = SampleSunLight(light, light_dir, inv_pdf, rng_state);
            pdf = 1.0 / max(inv_pdf, eps);
            max_distance = 1e9;
        } else if (light.type == 1) {
            radiance_light = SampleAreaLight(light, position, light_dir, inv_pdf, sampled_point, rng_state);
            pdf = 1.0 / max(inv_pdf, eps);
            max_distance = length(sampled_point - position);
        }

        if (pdf <= 0.0) {
            continue;
        }

        // Visibility to the light (hard shadows from geometry)
        if (!CastShadowRay(position + light_dir * 1e-3, light_dir, max_distance - 2e-3, rng_state)) {
            float phase = phase_HG(dot(light_dir, -wo), g);
            Ld += radiance_light * phase / pdf;
        }
    }
    return Ld;
}

// Procedural density in [0, 1] inside the volume
float DensityAtPoint(float3 p, VolumeRegion vol) {
    float3 size = vol.max_p - vol.min_p;
    // Avoid division by zero if bounds degenerate
    size = max(size, float3(1e-3, 1e-3, 1e-3));
    float3 local = saturate((p - vol.min_p) / size);

    // Uniform-ish dust for god rays, slightly denser at bottom
    float base = 1.0 - local.z;
    base = lerp(0.01, 0.1, base); // Very sparse dust

    // Subtle noise modulation to break uniformity slightly without "clumping"
    float noise = 0.8 + 0.4 * Noise3(p * 2.0); 
    
    return saturate(base * noise);
}

// Sample homogeneous volume
// Returns true if scattering happened, false otherwise
bool SampleHomogeneousVolume(
    inout RayDesc ray, 
    inout float3 throughput, 
    inout uint rng_state, 
    VolumeRegion vol, 
    float hit_dist,
    inout float3 radiance
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
    
    // 4. Accumulate volumetric emission
    // Emission contribution = Le * (1 - exp(-sigma_t * L)) / sigma_t
    // where L is the path length through the volume
    float emission_length;
    if (dist_sample < segment_length) {
        // Scattering event inside the medium
        // Emission path: from t_enter to t_enter + dist_sample
        emission_length = dist_sample;
    } else {
        // No scattering before exiting the volume
        // Emission path: from t_enter to t_exit (entire segment)
        emission_length = segment_length;
    }
    
    // Accumulate emission (handle sigma_t = 0 case)
    if (vol.sigma_t > eps) {
        float transmittance_factor = 1.0 - exp(-vol.sigma_t * emission_length);
        radiance += throughput * vol.emission * transmittance_factor / vol.sigma_t;
    } else {
        // When sigma_t is very small, use linear approximation
        radiance += throughput * vol.emission * emission_length;
    }
    
    if (dist_sample < segment_length) {
        // Scattering event inside the medium
        // PDF of this distance is sigma_t * exp(-sigma_t * dist)
        // Transmittance is exp(-sigma_t * dist)
        // Weight = (Trans * sigma_s) / PDF = sigma_s / sigma_t = albedo
        throughput *= albedo;
        // Single-scatter direct lighting with shadow ray visibility
        float3 Ld = EvaluateVolumeDirectLighting(ray.Origin + ray.Direction * (t_enter + dist_sample), -ray.Direction, vol.g, rng_state);
        radiance += throughput * Ld;
        ray.Origin = ray.Origin + ray.Direction * (t_enter + dist_sample);
        ray.Direction = sample_HG(ray.Direction, vol.g, rand(rng_state), rand(rng_state));
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
    float hit_dist,
    inout float3 radiance
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
            // Accumulate emission for the remaining segment (from previous t to t_exit)
            // Use the density at a point between previous position and t_exit
            float t_mid = (t - dist + t_exit) * 0.5;
            float3 pos_mid = ray.Origin + ray.Direction * t_mid;
            float density_mid = DensityAtPoint(pos_mid, vol);
            float remaining_dist = t_exit - (t - dist);
            radiance += throughput * vol.emission * density_mid * remaining_dist;
            return false;
        }

        float3 pos = ray.Origin + ray.Direction * t;
        float density = DensityAtPoint(pos, vol);
        float sigma_t_local = density * sigma_t_max;

        // Accumulate volumetric emission for this free-flight segment
        // Emission contribution = throughput * Le * density * dist
        // Note: In Delta Tracking, transmittance is handled probabilistically,
        // so we directly integrate using the free-flight distance
        radiance += throughput * vol.emission * density * dist;

        // Null-collision check
        // Probability of real collision: P = sigma_t_local / sigma_t_max
        if (rand(rng_state) < (sigma_t_local / sigma_t_max)) {
            // Real collision
            // Weight = albedo (same logic as homogeneous)
            throughput *= albedo;
            float3 Ld = EvaluateVolumeDirectLighting(pos, -ray.Direction, vol.g, rng_state);
            radiance += throughput * Ld;
            ray.Origin = pos;
            ray.Direction = sample_HG(ray.Direction, vol.g, rand(rng_state), rand(rng_state));
            ray.TMin = 1e-3;
            return true;
        }
        // Else: Null collision, continue (weight * 1.0)
    }

    return false;
}

#endif // VOLUME_HLSL

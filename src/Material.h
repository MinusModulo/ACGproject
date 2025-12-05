#pragma once
#include "long_march.h"

// Simple material structure for ray tracing
struct Material {

    // Base Color
    glm::vec4 base_color_factor;
    int base_color_tex;

    // Roughness, Metallic
    float roughness_factor;
    float metallic_factor;
    int metallic_roughness_tex;

    // Emission
    glm::vec3 emissive_factor;
    int emissive_texture;

    // Occulusion
    float AO_strength;
    int AO_texture;

    // Normal
    float normal_scale;
    int normal_texture;

    // alphaMode
    int alpha_mode; // 0: OPAQUE, 1: MASK, 2: BLEND
    
    // Transmission, IOR
    float transmission;
    float ior;

    Material()
        : base_color_factor(1.0f, 1.0f, 1.0f, 1.0f)
        , base_color_tex(-1) 

        , roughness_factor(0.5f)
        , metallic_factor(0.0f)
        , metallic_roughness_tex(-1)

        , emissive_factor(0.0f, 0.0f, 0.0f)
        , emissive_texture(-1)

        , AO_strength(1.0f)
        , AO_texture(-1)

        , normal_scale(1.0f)
        , normal_texture(-1)

        , alpha_mode(0)

        , transmission(0.0f)
        , ior(1.45f) {}

    Material(const glm::vec4& color,
             int base_color_texture = -1,

             float rough = 0.5f, 
             float metal = 0.0f,
             int metallic_roughness_texture = -1,

             const glm::vec3& emissive = glm::vec3(0.0f),
             int emissive_texture = -1,

             float ao_strength = 1.0f,
             int ao_texture = -1,

             float normal_scale = 1.0f,
             int normal_texture = -1,
             
             int alpha_mode = 0,

             float trans = 0.0f, 
             float index_of_refraction = 1.45f
             )
           : base_color_factor(color)
           , base_color_tex(base_color_texture) 

           , roughness_factor(rough)
           , metallic_factor(metal)
           , metallic_roughness_tex(metallic_roughness_texture)

           , emissive_factor(emissive)
           , emissive_texture(emissive_texture)

           , AO_strength(ao_strength)
           , AO_texture(ao_texture)

           , normal_scale(normal_scale)
           , normal_texture(normal_texture)

           , alpha_mode(alpha_mode)

           , transmission(trans)
           , ior(index_of_refraction) {}
};


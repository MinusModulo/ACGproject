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

    // Clearcoat
    float clearcoat_factor;
    float clearcoat_roughness_factor;

    // alphaMode
    int alpha_mode; // 0: OPAQUE, 1: MASK, 2: BLEND
    
    // Transmission, IOR
    float transmission;
    float ior;

    float dispersion;

    // ============================================================================
    // Multi-Layer Material: Layer 2 (Outer Layer) Properties
    // ============================================================================
    
    // Layer 2 Base Color
    glm::vec4 base_color_factor_layer2;
    int base_color_tex_layer2;

    // Layer 2 Roughness, Metallic
    float roughness_factor_layer2;
    float metallic_factor_layer2;
    int metallic_roughness_tex_layer2;

    // Layer 2 Emission
    glm::vec3 emissive_factor_layer2;
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

        , clearcoat_factor(0.0f)
        , clearcoat_roughness_factor(0.0f)

        , alpha_mode(0)

        , transmission(0.0f)
        , ior(1.45f)

        , dispersion(0.0f)

        // Layer 2 defaults
        , base_color_factor_layer2(1.0f, 1.0f, 1.0f, 1.0f)
        , base_color_tex_layer2(-1)
        , roughness_factor_layer2(0.5f)
        , metallic_factor_layer2(0.0f)
        , metallic_roughness_tex_layer2(-1)
        , emissive_factor_layer2(0.0f, 0.0f, 0.0f)
        , emissive_texture_layer2(-1)
        , AO_strength_layer2(1.0f)
        , AO_texture_layer2(-1)
        , normal_scale_layer2(1.0f)
        , normal_texture_layer2(-1)
        , clearcoat_factor_layer2(0.0f)
        , clearcoat_roughness_factor_layer2(0.0f)
        , alpha_mode_layer2(0)
        , transmission_layer2(0.0f)
        , ior_layer2(1.45f)
        , dispersion_layer2(0.0f)
        , thin(0.0f)
        , blend_factor(0.0f)
        , layer_thickness(0.0f) {}

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
             
             float clearcoat = 0.0f,
             float clearcoat_roughness = 0.0f,

             int alpha_mode = 0,

             float trans = 0.0f, 
             float index_of_refraction = 1.45f,

             float dispersion = 0.0f
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

           , clearcoat_factor(clearcoat)
           , clearcoat_roughness_factor(clearcoat_roughness)

           , normal_scale(normal_scale)
           , normal_texture(normal_texture)

           , alpha_mode(alpha_mode)

           , transmission(trans)
           , ior(index_of_refraction) 
           
           , dispersion(dispersion)

           // Layer 2 defaults
           , base_color_factor_layer2(1.0f, 1.0f, 1.0f, 1.0f)
           , base_color_tex_layer2(-1)
           , roughness_factor_layer2(0.5f)
           , metallic_factor_layer2(0.0f)
           , metallic_roughness_tex_layer2(-1)
           , emissive_factor_layer2(0.0f, 0.0f, 0.0f)
           , emissive_texture_layer2(-1)
           , AO_strength_layer2(1.0f)
           , AO_texture_layer2(-1)
           , normal_scale_layer2(1.0f)
           , normal_texture_layer2(-1)
           , clearcoat_factor_layer2(0.0f)
           , clearcoat_roughness_factor_layer2(0.0f)
           , alpha_mode_layer2(0)
           , transmission_layer2(0.0f)
           , ior_layer2(1.45f)
           , dispersion_layer2(0.0f)
           , thin(0.0f)
           , blend_factor(0.0f)
           , layer_thickness(0.0f) {}
};


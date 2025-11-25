#pragma once
#include "long_march.h"

// Simple material structure for ray tracing
struct Material {
    glm::vec3 base_color;
    float roughness;
    glm::vec3 emission;
    float metallic;

    Material()
        : base_color(0.8f, 0.8f, 0.8f)
        , roughness(0.5f)
        , metallic(0.0f)
        , emission(0.0f, 0.0f, 0.0f) {}

    Material(const glm::vec3& color, float rough = 0.5f, float metal = 0.0f, const glm::vec3& emit = glm::vec3(0.0f))
        : base_color(color)
        , roughness(rough)
        , metallic(metal)
        , emission(emit) {}
};


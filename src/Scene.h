#pragma once
#include "long_march.h"
#include "Entity.h"
#include "Material.h"
#include <vector>
#include <memory>

enum LightType {
    LIGHT_POINT = 0,
    LIGHT_AREA = 1,
    LIGHT_SUN = 2
};

struct Light {
    LightType type;
    glm::vec3 color;
    float intensity;

    glm::vec3 position;
    glm::vec3 direction;
    glm::vec3 u;
    glm::vec3 v;
};

// This struct model is for storing all emissive triangle
// I'm not sure if this is efficient or not
struct LightTriangle {
    glm::vec3 v0; float pad0;
    glm::vec3 v1; float pad1;
    glm::vec3 v2; float pad2;
    glm::vec3 emission; float pad3;
};

// Scene manages a collection of entities and builds the TLAS
class Scene {
public:
    Scene(grassland::graphics::Core* core);
    ~Scene();

    // Add an entity to the scene
    void AddEntity(std::shared_ptr<Entity> entity);

    // Remove all entities
    void Clear();

    // Build/rebuild the TLAS from all entities
    void BuildAccelerationStructures();

    // Update TLAS instances (e.g., for animation)
    void UpdateInstances();

    // Build from .glb file
    void LoadFromGLB(const std::string& glb_file_path);

    // Get the TLAS for rendering
    grassland::graphics::AccelerationStructure* GetTLAS() const { return tlas_.get(); }

    // Get materials buffer for all entities
    grassland::graphics::Buffer* GetMaterialsBuffer() const { return materials_buffer_.get(); }

    // Get all entities
    const std::vector<std::shared_ptr<Entity>>& GetEntities() const { return entities_; }

    // Add a light to the scene
    void AddLight(const Light& light);

    // Remove all lights
    void ClearLights();

    // Get all lights
    const std::vector<Light>& GetLights() const { return lights_; }
    // Get number of entities
    size_t GetEntityCount() const { return entities_.size(); }

        // Get number of lights
    size_t GetLightCount() const { return lights_.size(); }

    // Get lights buffer for rendering
    grassland::graphics::Buffer* GetLightsBuffer() const { return lights_buffer_.get(); }

    // Get all vertex buffers
    std::vector<grassland::graphics::Buffer*> GetVertexBuffers() const { return vertex_buffers_; }

    // Get all index buffers
    std::vector<grassland::graphics::Buffer*> GetIndexBuffers() const { return index_buffers_; }

    // Get all normal buffers
    std::vector<grassland::graphics::Buffer*> GetNormalBuffers() const { return normal_buffers_; }

    // Get all texcoord buffers
    std::vector<grassland::graphics::Buffer*> GetTexcoordBuffers() const { return texcoord_buffers_; }

    // Get all tangent buffers
    std::vector<grassland::graphics::Buffer*> GetTangentBuffers() const { return tangent_buffers_; }

    // Get base color texture count
    size_t GetBaseColorTextureCount() const { return base_color_srvs_.size(); }

    // Add a texture to the scene (takes ownership)
    int AddTexture(std::unique_ptr<grassland::graphics::Image> texture);
    
    // Follow the order of entity, create and attach texcoord buffer
    //void CreateAndAttachTexcoordBuffer(const std::vector<glm::vec2>& uvs);

    // Get base color texture SRV array
    std::vector<grassland::graphics::Image*> GetBaseColorTextureSRVs() const { return base_color_srvs_; }

    // Base color textures SRV array setter
    void SetBaseColorTextures(const std::vector<grassland::graphics::Image*>& srvs) { base_color_srvs_ = srvs; }

    // Get linear wrap sampler
    grassland::graphics::Sampler* GetLinearWrapSampler() const { return linear_wrap_sampler_; }

    // Build linear wrap sampler
    void BuildSampler();

    // ============================================================================
    // Multi-Layer Material Support
    // ============================================================================
    
    // Get entity by index
    std::shared_ptr<Entity> GetEntity(size_t index) const {
        if (index >= entities_.size()) return nullptr;
        return entities_[index];
    }
    
    // Get core pointer (for texture loading)
    grassland::graphics::Core* GetCore() const { return core_; }
    
    // Apply multi-layer material to an entity
    void ApplyMultiLayerMaterial(size_t entity_index,
                                 const Material& layer2,
                                 float thin = 0.0f,
                                 float blend_factor = 0.5f,
                                 float layer_thickness = 0.001f);

    // Set skybox texture
    void SetSkyboxTexture(std::unique_ptr<grassland::graphics::Image> texture);
    
    // Get skybox texture
    grassland::graphics::Image* GetSkyboxTexture() const { return skybox_texture_.get(); }

private:
    void UpdateMaterialsBuffer();
    void UpdateLightsBuffer();

    grassland::graphics::Core* core_;
    std::vector<std::shared_ptr<Entity>> entities_;
    std::vector<Light> lights_;
    std::unique_ptr<grassland::graphics::AccelerationStructure> tlas_;
    std::unique_ptr<grassland::graphics::Buffer> materials_buffer_;
    std::unique_ptr<grassland::graphics::Buffer> lights_buffer_;
    std::vector<grassland::graphics::Buffer*> vertex_buffers_;
    std::vector<grassland::graphics::Buffer*> index_buffers_;
    std::vector<grassland::graphics::Buffer*> normal_buffers_;
    std::vector<grassland::graphics::Buffer*> tangent_buffers_;
    std::vector<grassland::graphics::Buffer*> texcoord_buffers_;
    std::vector<grassland::graphics::Image*> base_color_srvs_;
    std::vector<std::unique_ptr<grassland::graphics::Image>> texture_storage_; // Owns the textures
    std::unique_ptr<grassland::graphics::Image> skybox_texture_;
    grassland::graphics::Sampler* linear_wrap_sampler_ = nullptr;
};


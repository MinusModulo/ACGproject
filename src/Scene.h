#pragma once
#include "long_march.h"
#include "Entity.h"
#include "Material.h"
#include <vector>
#include <memory>

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

    // Get the TLAS for rendering
    grassland::graphics::AccelerationStructure* GetTLAS() const { return tlas_.get(); }

    // Get materials buffer for all entities
    grassland::graphics::Buffer* GetMaterialsBuffer() const { return materials_buffer_.get(); }

    // Get all entities
    const std::vector<std::shared_ptr<Entity>>& GetEntities() const { return entities_; }

    // Get number of entities
    size_t GetEntityCount() const { return entities_.size(); }

    // Get all vertex buffers
    std::vector<grassland::graphics::Buffer*> GetVertexBuffers() const { return vertex_buffers_; }

    // Get all index buffers
    std::vector<grassland::graphics::Buffer*> GetIndexBuffers() const { return index_buffers_; }

    grassland::graphics::Buffer* GetEmissiveTriangleBuffer() const { return light_triangles_buffer_.get(); }
private:
    void UpdateMaterialsBuffer();
    void UpdateEmissiveTriangleBuffer();

    grassland::graphics::Core* core_;
    std::vector<std::shared_ptr<Entity>> entities_;
    std::unique_ptr<grassland::graphics::AccelerationStructure> tlas_;
    std::unique_ptr<grassland::graphics::Buffer> materials_buffer_;
    std::vector<grassland::graphics::Buffer*> vertex_buffers_;
    std::vector<grassland::graphics::Buffer*> index_buffers_;
    std::unique_ptr<grassland::graphics::Buffer> light_triangles_buffer_; // the indices of emissive entities
};


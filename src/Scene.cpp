#include "Scene.h"

Scene::Scene(grassland::graphics::Core* core)
    : core_(core) {
}

Scene::~Scene() {
    Clear();
}

void Scene::AddEntity(std::shared_ptr<Entity> entity) {
    if (!entity || !entity->IsValid()) {
        grassland::LogError("Cannot add invalid entity to scene");
        return;
    }

    // Build BLAS for the entity
    entity->BuildBLAS(core_);
    
    entities_.push_back(entity);
    vertex_buffers_.push_back(entity->GetVertexBuffer());
    index_buffers_.push_back(entity->GetIndexBuffer());
    grassland::LogInfo("Added entity to scene (total: {})", entities_.size());
}

void Scene::Clear() {
    entities_.clear();
    tlas_.reset();
    materials_buffer_.reset();
    vertex_buffers_.clear();
    index_buffers_.clear();
}

void Scene::BuildAccelerationStructures() {
    if (entities_.empty()) {
        grassland::LogWarning("No entities to build acceleration structures");
        return;
    }

    // Create TLAS instances from all entities
    std::vector<grassland::graphics::RayTracingInstance> instances;
    instances.reserve(entities_.size());

    for (size_t i = 0; i < entities_.size(); ++i) {
        auto& entity = entities_[i];
        if (entity->GetBLAS()) {
            // Create instance with entity's transform
            // instanceCustomIndex is used to index into materials buffer
            // Convert mat4 to mat4x3 (drop the last row which is always [0,0,0,1] for affine transforms)
            glm::mat4x3 transform_3x4 = glm::mat4x3(entity->GetTransform());
            
            auto instance = entity->GetBLAS()->MakeInstance(
                transform_3x4,
                static_cast<uint32_t>(i),  // instanceCustomIndex for material lookup
                0xFF,                       // instanceMask
                0,                          // instanceShaderBindingTableRecordOffset
                grassland::graphics::RAYTRACING_INSTANCE_FLAG_NONE
            );
            instances.push_back(instance);
        }
    }

    // Build TLAS
    core_->CreateTopLevelAccelerationStructure(instances, &tlas_);
    grassland::LogInfo("Built TLAS with {} instances", instances.size());

    // Update materials buffer
    UpdateMaterialsBuffer();
    // Update emissive triangle buffer
    UpdateEmissiveTriangleBuffer();
}

void Scene::UpdateInstances() {
    if (!tlas_ || entities_.empty()) {
        return;
    }

    // Recreate instances with updated transforms
    std::vector<grassland::graphics::RayTracingInstance> instances;
    instances.reserve(entities_.size());

    for (size_t i = 0; i < entities_.size(); ++i) {
        auto& entity = entities_[i];
        if (entity->GetBLAS()) {
            // Convert mat4 to mat4x3
            glm::mat4x3 transform_3x4 = glm::mat4x3(entity->GetTransform());
            
            auto instance = entity->GetBLAS()->MakeInstance(
                transform_3x4,
                static_cast<uint32_t>(i),
                0xFF,
                0,
                grassland::graphics::RAYTRACING_INSTANCE_FLAG_NONE
            );
            instances.push_back(instance);
        }
    }

    // Update TLAS
    tlas_->UpdateInstances(instances);
}

void Scene::UpdateMaterialsBuffer() {
    if (entities_.empty()) {
        return;
    }

    // Collect all materials
    std::vector<Material> materials;
    materials.reserve(entities_.size());

    for (const auto& entity : entities_) {
        materials.push_back(entity->GetMaterial());
    }

    // Create/update materials buffer
    size_t buffer_size = materials.size() * sizeof(Material);
    
    if (!materials_buffer_) {
        core_->CreateBuffer(buffer_size, 
                          grassland::graphics::BUFFER_TYPE_DYNAMIC, 
                          &materials_buffer_);
    }
    
    materials_buffer_->UploadData(materials.data(), buffer_size);
    grassland::LogInfo("Updated materials buffer with {} materials", materials.size());
}

void Scene::UpdateEmissiveTriangleBuffer() {
    if (entities_.empty()) {
        return;
    }

    std::vector<LightTriangle> light_triangles;

    for (const auto& entity : entities_) {
        const Material& mat = entity->GetMaterial();
        if (mat.emission != glm::vec3(0.0f)) {
            const auto& mesh = entity->GetMesh();
            const uint32_t* indices = mesh.Indices();
            const auto& positions = mesh.Positions();

            glm::mat4 transform = entity->GetTransform();

            for (size_t i = 0; i < mesh.NumIndices(); i += 3) {
                uint32_t idx0 = indices[i];
                uint32_t idx1 = indices[i + 1];
                uint32_t idx2 = indices[i + 2];

                glm::vec3 v0_obj(positions[idx0].x(), positions[idx0].y(), positions[idx0].z());
                glm::vec3 v1_obj(positions[idx1].x(), positions[idx1].y(), positions[idx1].z());
                glm::vec3 v2_obj(positions[idx2].x(), positions[idx2].y(), positions[idx2].z());

                glm::vec3 v0_world = transform * glm::vec4(v0_obj, 1.0f);
                glm::vec3 v1_world = transform * glm::vec4(v1_obj, 1.0f);
                glm::vec3 v2_world = transform * glm::vec4(v2_obj, 1.0f);

                LightTriangle light_triangle;
                light_triangle.v0 = v0_world;
                light_triangle.v1 = v1_world;
                light_triangle.v2 = v2_world;
                light_triangle.emission = mat.emission;

                light_triangle.pad0 = 0.0f;
                light_triangle.pad1 = 0.0f;
                light_triangle.pad2 = 0.0f;
                light_triangle.pad3 = 0.0f;

                light_triangles.push_back(light_triangle);
            }
        }
    }

    // Create/update light triangles buffer
    size_t buffer_size = light_triangles.size() * sizeof(LightTriangle);

    if (buffer_size == 0) {
        // Create a dummy buffer if no lights exist to avoid binding errors
        buffer_size = sizeof(LightTriangle);
        light_triangles.resize(1);
    }

    if (!light_triangles_buffer_ || light_triangles_buffer_->Size() < buffer_size) {
        core_->CreateBuffer(buffer_size, 
                          grassland::graphics::BUFFER_TYPE_DYNAMIC, 
                          &light_triangles_buffer_);
    }
    
    light_triangles_buffer_->UploadData(light_triangles.data(), buffer_size);
    grassland::LogInfo("Updated light triangles buffer with {} triangles", light_triangles.size());
}
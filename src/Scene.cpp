#include "Scene.h"
#include "tiny_gltf.cc"
#include <glm/gtc/type_ptr.hpp>


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
    normal_buffers_.push_back(entity->GetNormalBuffer());
    tangent_buffers_.push_back(entity->GetTangentBuffer());
    texcoord_buffers_.push_back(entity->GetTexcoordBuffer());
    grassland::LogInfo("Added entity to scene (total: {})", entities_.size());
}
void Scene::AddLight(const Light& light) {
    lights_.push_back(light);
    UpdateLightsBuffer();
}

int Scene::AddTexture(std::unique_ptr<grassland::graphics::Image> texture) {
    if (!texture) return -1;
    base_color_srvs_.push_back(texture.get());
    texture_storage_.push_back(std::move(texture));
    return static_cast<int>(base_color_srvs_.size() - 1);
}

void Scene::ClearLights() {
    lights_.clear();
    lights_buffer_.reset();
}
void Scene::Clear() {
    entities_.clear();
    lights_.clear();
    tlas_.reset();
    materials_buffer_.reset();
    lights_buffer_.reset();
    vertex_buffers_.clear();
    index_buffers_.clear();
    normal_buffers_.clear();
    tangent_buffers_.clear();
    texcoord_buffers_.clear();
    base_color_srvs_.clear();
    texture_storage_.clear();
    linear_wrap_sampler_ = nullptr;
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

void Scene::UpdateLightsBuffer() {
    if (lights_.empty()) {
        lights_buffer_.reset();
        return;
    }
	// Create/update lights buffer
	size_t buffer_size = lights_.size() * sizeof(Light);
	buffer_size = std::max(buffer_size, sizeof(Light)); // Ensure non-zero size

	if (!lights_buffer_) {
		core_->CreateBuffer(buffer_size,
			grassland::graphics::BUFFER_TYPE_DYNAMIC,
			&lights_buffer_);
	}

	lights_buffer_->UploadData(lights_.data(), buffer_size);
	grassland::LogInfo("Updated lights buffer with {} lights", lights_.size());
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

void Scene::BuildSampler() {
    if (!linear_wrap_sampler_) {
        grassland::graphics::SamplerInfo info{};
        info.min_filter = grassland::graphics::FILTER_MODE_LINEAR;
        info.mag_filter = grassland::graphics::FILTER_MODE_LINEAR;
        info.mip_filter = grassland::graphics::FILTER_MODE_LINEAR;
        info.address_mode_u = grassland::graphics::ADDRESS_MODE_REPEAT;
        info.address_mode_v = grassland::graphics::ADDRESS_MODE_REPEAT;
        info.address_mode_w = grassland::graphics::ADDRESS_MODE_REPEAT;
        core_->CreateSampler(info, &linear_wrap_sampler_);
        grassland::LogInfo("Created linear wrap sampler");
    }
}

void Scene::LoadFromGLB(const std::string& gltf_path) {
    tinygltf::Model model;
    tinygltf::TinyGLTF loader;
    std::string err, warn;
    bool ok = loader.LoadBinaryFromFile(&model, &err, &warn, gltf_path);

    if (!warn.empty()) {
        grassland::LogWarning("glTF warn: {}", warn);
    }

    if (!ok) {
        grassland::LogError("Failed to load {}", gltf_path, err);
        return ;
    }

    grassland::LogInfo("Loaded glTF: scenes={}, meshes={}, materials={}, textures={}",
                        model.scenes.size(), model.meshes.size(), model.materials.size(), model.textures.size());
    
    // Step 1 : Load textures to GPU and create Shader Resource Views
    std::vector<grassland::graphics::Image*> baseColorSRVs;
    baseColorSRVs.reserve(model.textures.size()); // Total textures
    
    for (size_t ti = 0; ti < model.textures.size(); ++ti) {
        // 首先 texture 会有一个连到对应 image 的 source 索引，我们把它对应的 image 找到
        const auto &tex = model.textures[ti];
        if (tex.source < 0 || tex.source >= (int)model.images.size()) {
            baseColorSRVs.push_back(nullptr); // Don't forget we need to keep the index consistent
            grassland::LogWarning("Texture {} has invalid source {}", (int)ti, tex.source);
            continue;
        }
        const auto &img = model.images[tex.source];

        // 接着，transform image to a R8G8B8A8_UNORM format
        int w = img.width;
        int h = img.height;
        int comp = img.component;
        if (comp != 4) {
            grassland::LogWarning("Texture {} has {} components; expected RGBA4. Will pad.", (int)ti, comp);
        }
        std::vector<uint8_t> rgba;
        rgba.resize(w * h * 4, 255);
        // Copy/pad channels
        for (int y = 0; y < h; ++y) {
            for (int x = 0; x < w; ++x) {
                int dst = (y * w + x) * 4;
                int src = (y * w + x) * comp;
                for (int c = 0; c < comp && c < 4; ++c) rgba[dst + c] = img.image[src + c];
                if (comp < 4) rgba[dst + 3] = 255;
            }
        }

        // 把这个图读进去
        grassland::graphics::Image *gpuImage = nullptr;
        core_->CreateImage(w, h, grassland::graphics::IMAGE_FORMAT_R8G8B8A8_UNORM, &gpuImage);
        gpuImage->UploadData(rgba.data()); // .data() 返回指针
        baseColorSRVs.push_back(gpuImage);

        // grassland::LogInfo("Created GPU texture {} ({}x{}, comp={})", (int)ti, w, h, comp);
    }

    // Convert glTF meshes to Entities
    for (const auto &node : model.nodes) {
        if (node.mesh < 0) {
            grassland::LogWarning("Node {} has no mesh, skipping", node.name);
            continue;
        }
        const auto &mesh = model.meshes[node.mesh];

        // transform matrix
        glm::mat4 transform(1.0f);
        // glTF 有两种情况：变换矩阵 and T/R/S，都要考虑
        if (!node.matrix.empty()) {
            transform = glm::make_mat4(node.matrix.data());
        } else {
            glm::vec3 t(0.0f), s(1.0f);
            glm::quat r(1, 0, 0, 0);
            if (!node.translation.empty()) t = glm::vec3(node.translation[0], node.translation[1], node.translation[2]);
            if (!node.scale.empty()) s = glm::vec3(node.scale[0], node.scale[1], node.scale[2]);
            if (!node.rotation.empty()) r = glm::quat((float)node.rotation[3], (float)node.rotation[0], (float)node.rotation[1], (float)node.rotation[2]);
            transform = glm::translate(glm::mat4(1.0f), t) * glm::mat4_cast(r) * glm::scale(glm::mat4(1.0f), s);
        }
        
        // Process each primitive in the mesh
        for (const auto &prim : mesh.primitives) {

            /*
             * mesh理论上有 5 种东西。
             * pos 存储的是这个 mesh 的本地的所有顶点的位置。
             * uv 存储的是这个 mesh 的本地的所有顶点的纹理坐标。
             * indices 存储的是组成这个 mesh 的三角形的顶点索引，也是本地的。  
             * 还有一直被我忘掉的法线。
             * 还有我都没见过的 tangent, tkpl
             */

            // 1 : position, a vec3
            auto posIt = prim.attributes.find("POSITION");
            if (posIt == prim.attributes.end()) {
                grassland::LogWarning("Primitive missing POSITION attribute, skipping");
                continue;
            }
            
            const auto &posAccessor = model.accessors[posIt->second];
            const auto &posView = model.bufferViews[posAccessor.bufferView];
            const auto &posBuf = model.buffers[posView.buffer];
            const uint8_t *posData = posBuf.data.data() + posView.byteOffset + posAccessor.byteOffset;
            size_t posStride = posAccessor.ByteStride(posView);
            if (posStride <= 0) {
                grassland::LogWarning("Invalid POSITION accessor byte stride, use default");
                posStride = sizeof(float) * 3;
            }

            // 2 : uv textcoordinate, a vec2
            auto uvIt = prim.attributes.find("TEXCOORD_0");
            const uint8_t *uvData = nullptr;
            size_t uvStride = 0;
            size_t uvCount = 0;
            if (uvIt == prim.attributes.end()) {
                grassland::LogWarning("Primitive missing TEXCOORD_0 attribute, use default");
            } else {
                const auto &uvAccessor = model.accessors[uvIt->second];
                const auto &uvView = model.bufferViews[uvAccessor.bufferView];
                const auto &uvBuf = model.buffers[uvView.buffer];
                uvData = uvBuf.data.data() + uvView.byteOffset + uvAccessor.byteOffset;
                uvStride = uvAccessor.ByteStride(uvView);
                if (uvStride <= 0) {
                    grassland::LogWarning("Invalid TEXCOORD_0 accessor byte stride, use default");
                    uvStride = sizeof(float) * 2;
                }
                uvCount = uvAccessor.count;
            }

            // 3 : indices
            if (prim.indices < 0) {
                grassland::LogWarning("Primitive without indices not supported, skipping");
                continue;
            }

            const auto &idxAccessor = model.accessors[prim.indices];
            const auto &idxView = model.bufferViews[idxAccessor.bufferView];
            const auto &idxBuf = model.buffers[idxView.buffer];
            const uint8_t *idxData = idxBuf.data.data() + idxView.byteOffset + idxAccessor.byteOffset;

            // 4 : normals

            auto normalIt = prim.attributes.find("NORMAL");
            const uint8_t *normalData = nullptr;
            size_t normalStride = 0;
            size_t normalCount = 0;
            if (normalIt == prim.attributes.end()) {
                grassland::LogWarning("Primitive missing NORMAL attribute, use default");
            } else {
                grassland::LogInfo("Found NORMAL attribute for node {}", node.name);
                const auto &normalAccessor = model.accessors[normalIt->second];
                const auto &normalView = model.bufferViews[normalAccessor.bufferView];
                const auto &normalBuf = model.buffers[normalView.buffer];
                normalData = normalBuf.data.data() + normalView.byteOffset + normalAccessor.byteOffset;
                normalStride = normalAccessor.ByteStride(normalView);
                if (normalStride <= 0) {
                    grassland::LogWarning("Invalid NORMAL accessor byte stride, use default");
                    normalStride = sizeof(float) * 3;
                }
                normalCount = normalAccessor.count;
            }

            // 5 : tangent 

            auto tangentIt = prim.attributes.find("TANGENT");
            const uint8_t *tangentData = nullptr;
            size_t tangentStride = 0;
            size_t tangentCount = 0;
            if (tangentIt == prim.attributes.end()) {
                grassland::LogWarning("Primitive missing TANGENT attribute, use default");
            } else {
                grassland::LogInfo("Found TANGENT attribute for node {}", node.name);
                const auto &tangentAccessor = model.accessors[tangentIt->second];
                const auto &tangentView = model.bufferViews[tangentAccessor.bufferView];
                const auto &tangentBuf = model.buffers[tangentView.buffer];
                tangentData = tangentBuf.data.data() + tangentView.byteOffset + tangentAccessor.byteOffset;
                tangentStride = tangentAccessor.ByteStride(tangentView);
                if (tangentStride <= 0) {
                    grassland::LogWarning("Invalid TANGENT accessor byte stride, use default");
                    tangentStride = sizeof(float) * 4;
                }
                tangentCount = tangentAccessor.count;
            }

            // 5 个 data 的位置准备好了，开始一个一个读取。
            const size_t vertex_count = posAccessor.count;
            std::vector<grassland::Vector3<float>> positions(vertex_count);
            std::vector<grassland::Vector2<float>> texcoords;
            std::vector<glm::vec2> upload_uvs;
            std::vector<grassland::Vector3<float>> normals(vertex_count);
            std::vector<grassland::Vector3<float>> tangents(vertex_count);

            if (uvData) {
                texcoords.resize(vertex_count, grassland::Vector2<float>(0.0f, 0.0f));
                upload_uvs.resize(vertex_count, glm::vec2(0.0f));
            } else {
                upload_uvs.resize(vertex_count, glm::vec2(0.0f));
            }

            for (size_t i = 0; i < vertex_count; ++i) {
                const float *p = reinterpret_cast<const float *>(posData + i * posStride);
                positions[i] = grassland::Vector3<float>(p[0], p[1], p[2]);
                if (uvData && i < uvCount) {
                    const float *q = reinterpret_cast<const float *>(uvData + i * uvStride);
                    texcoords[i] = grassland::Vector2<float>(q[0], q[1]);
                    upload_uvs[i] = glm::vec2(q[0], q[1]);
                }
                if (normalData && i < normalCount) {
                    const float *n = reinterpret_cast<const float *>(normalData + i * normalStride);
                    normals[i] = grassland::Vector3<float>(n[0], n[1], n[2]);
                }
                if (tangentData && i < tangentCount) {
                    const float *t = reinterpret_cast<const float *>(tangentData + i * tangentStride);
                    if (t[3] != 1.0f)
                        grassland::LogWarning("Tangent w component is not 1.0f");
                    tangents[i] = grassland::Vector3<float>(t[0], t[1], t[2]);
                }
            }

            std::vector<uint32_t> indices(idxAccessor.count);
            if (idxAccessor.componentType == TINYGLTF_COMPONENT_TYPE_UNSIGNED_SHORT) {
                const uint16_t *src = reinterpret_cast<const uint16_t *>(idxData);
                for (size_t i = 0; i < idxAccessor.count; ++i) indices[i] = static_cast<uint32_t>(src[i]);
            } else if (idxAccessor.componentType == TINYGLTF_COMPONENT_TYPE_UNSIGNED_INT) {
                const uint32_t *src = reinterpret_cast<const uint32_t *>(idxData);
                for (size_t i = 0; i < idxAccessor.count; ++i) indices[i] = src[i];
            } else if (idxAccessor.componentType == TINYGLTF_COMPONENT_TYPE_UNSIGNED_BYTE) {
                const uint8_t *src = reinterpret_cast<const uint8_t *>(idxData);
                for (size_t i = 0; i < idxAccessor.count; ++i) indices[i] = static_cast<uint32_t>(src[i]);
            } else {
                grassland::LogError("Unsupported index type in glTF");
                continue;
            }

            // 最后, the material
            Material mat(glm::vec4(1.0f), 0.5f, 0.0f);
            if (prim.material < 0 || prim.material >= static_cast<int>(model.materials.size())) {
                grassland::LogWarning("Primitive has no material, use default");
            } else {
                const auto &gm = model.materials[prim.material];
                /*
                我要从 material 里拿出
                - baseColorFactor (vec4)
                - roughnessFactor (float)
                - metallicFactor (float)
                - emissiveFactor (vec3)
                - baseColorTexture (texture index)
                - metallicRoughnessTexture (texture index)
                - emissiveTexture (texture index)
                - normalTexture (texture index)
                - alphaMode (string)
                */
                const auto &pbrMR = gm.pbrMetallicRoughness;
                glm::vec4 baseColor = glm::vec4(pbrMR.baseColorFactor[0], pbrMR.baseColorFactor[1], pbrMR.baseColorFactor[2], pbrMR.baseColorFactor[3]);
                float rough = pbrMR.roughnessFactor;
                float metallic = pbrMR.metallicFactor;
                glm::vec3 emissive = glm::vec3(gm.emissiveFactor[0], gm.emissiveFactor[1], gm.emissiveFactor[2]);
                int baseColTexIndex = pbrMR.baseColorTexture.index;
                int metalRoughTexIndex = pbrMR.metallicRoughnessTexture.index;
                int emissiveTexIndex = gm.emissiveTexture.index;
                float aoStrength = gm.occlusionTexture.strength;
                int aoTexIndex = gm.occlusionTexture.index;
                int normalTexIndex = gm.normalTexture.index;
                float normalScale = gm.normalTexture.scale;

                int alphaMode = 0;
                if (gm.alphaMode == "MASK") {
                    alphaMode = 1;
                } else if (gm.alphaMode == "BLEND") {
                    alphaMode = 2;
                } else {
                    alphaMode = 0;
                }

                mat = Material(
                    baseColor, baseColTexIndex, 
                    rough, metallic, metalRoughTexIndex,
                    emissive, emissiveTexIndex, 
                    aoStrength, aoTexIndex,
                    normalScale, normalTexIndex,
                    alphaMode,
                    0.0f, 1.45f
                );
            }

            const grassland::Vector2<float> *texcoord_ptr = texcoords.empty() ? nullptr : texcoords.data();
            const grassland::Vector3<float> *normal_ptr = normals.empty() ? nullptr : normals.data();
            const grassland::Vector3<float> *tangent_ptr = tangents.empty() ? nullptr : tangents.data();
            grassland::Mesh<float> mesh_asset(
                vertex_count,
                indices.size(),
                indices.data(),
                positions.data(),
                normal_ptr,
                texcoord_ptr,
                tangent_ptr);

            auto entity = std::make_shared<Entity>(mesh_asset, mat, transform);
            AddEntity(entity);
        }
    }

    // Register texture SRVs array to scene for binding
    SetBaseColorTextures(baseColorSRVs);
}

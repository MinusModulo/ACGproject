# 多层材质物体创建与导入指南

## 一、准备多层材质模型和纹理

### 1.1 从网上下载模型和纹理

推荐资源：
- **Sketchfab** (https://sketchfab.com)：搜索 "multi-layer material"、"coated material"、"painted material"
- **Poly Haven** (https://polyhaven.com)：提供高质量材质资源
- **CC0 Textures** (https://cc0textures.com)：提供免费材质纹理
- **AmbientCG** (https://ambientcg.com)：提供 CC0 材质纹理包（如 Metal053B_1K-JPG）

### 1.2 模型要求

1. **格式**：支持 glTF 2.0 (.glb 或 .gltf)
2. **材质信息**：模型需要包含材质信息（不能只是几何体）
3. **纹理**：最好包含完整的纹理贴图（baseColor, metallicRoughness, normal 等）

### 1.3 纹理要求

对于多层材质，需要准备：
- **第一层（底层）材质纹理**：如果需要纹理的话
- **第二层（外层）材质纹理**：
  - Base Color（基础颜色）- 如 `Metal053B_1K-JPG_Color.jpg`
  - Metallic（金属度）- 如 `Metal053B_1K-JPG_Metalness.jpg`
  - Roughness（粗糙度）- 如 `Metal053B_1K-JPG_Roughness.jpg`
  - Normal（法线贴图）- 如 `Metal053B_1K-JPG_NormalGL.jpg`（OpenGL 格式）或 `NormalDX.jpg`（DirectX 格式）
  - （可选）AO、Emissive 等

**注意**：
- 法线贴图格式：OpenGL 格式（NormalGL）或 DirectX 格式（NormalDX），根据渲染管线选择
- 如果 metallic 和 roughness 在同一张纹理中，需要分离或创建组合纹理
- 纹理文件应放在项目的 `assets/` 目录下

## 二、创建和应用多层材质

**注意**：由于不修改 tinygltf 导入逻辑，多层材质需要在代码中手动创建和应用，而不是从 glTF 文件导入。

### 方法 1：代码中直接创建（推荐）

在加载模型后，通过代码创建和应用多层材质：

#### 步骤 1：加载模型（正常加载，只包含第一层材质）
```cpp
// 在 app.cpp 的 OnInit() 或类似位置
scene_->LoadFromGLB("assets/models/your_model.glb");
```

#### 步骤 2：准备第二层材质的纹理
确保第二层材质的纹理已经加载到场景中：
```cpp
// 如果纹理在 glTF 中，会自动加载
// 如果需要额外加载纹理：
int layer2_base_color_tex = scene_->LoadTexture("textures/layer2_basecolor.png");
int layer2_metallic_roughness_tex = scene_->LoadTexture("textures/layer2_metallic_roughness.png");
int layer2_normal_tex = scene_->LoadTexture("textures/layer2_normal.png");
```

#### 步骤 3：创建第二层材质
```cpp
Material layer2(
    glm::vec4(1.0f, 0.2f, 0.2f, 1.0f),  // 红色涂层
    layer2_base_color_tex,
    0.1f, 0.9f,                          // 光滑、金属
    layer2_metallic_roughness_tex,
    glm::vec3(0.0f),                     // 无自发光
    -1,                                  // 无自发光纹理
    1.0f, -1,                            // AO
    1.0f, layer2_normal_tex             // 法线
);
```

#### 步骤 4：应用多层材质到 Entity
```cpp
// 获取需要多层材质的 Entity（通过索引或名称）
auto entity = scene_->GetEntity(0);  // 假设是第一个 Entity

// 获取第一层材质（从 glTF 加载的）
Material multi_layer = entity->GetMaterial();

// 复制第二层属性
multi_layer.base_color_factor_layer2 = layer2.base_color_factor;
multi_layer.base_color_tex_layer2 = layer2.base_color_tex;
multi_layer.roughness_factor_layer2 = layer2.roughness_factor;
multi_layer.metallic_factor_layer2 = layer2.metallic_factor;
multi_layer.metallic_roughness_tex_layer2 = layer2.metallic_roughness_tex;
multi_layer.emissive_factor_layer2 = layer2.emissive_factor;
multi_layer.emissive_texture_layer2 = layer2.emissive_texture;
multi_layer.AO_strength_layer2 = layer2.AO_strength;
multi_layer.AO_texture_layer2 = layer2.AO_texture;
multi_layer.normal_scale_layer2 = layer2.normal_scale;
multi_layer.normal_texture_layer2 = layer2.normal_texture;
multi_layer.clearcoat_factor_layer2 = layer2.clearcoat_factor;
multi_layer.clearcoat_roughness_factor_layer2 = layer2.clearcoat_roughness_factor;
multi_layer.alpha_mode_layer2 = layer2.alpha_mode;
multi_layer.transmission_layer2 = layer2.transmission;
multi_layer.ior_layer2 = layer2.ior;
multi_layer.dispersion_layer2 = layer2.dispersion;

// 设置多层材质控制参数
multi_layer.thin = 0.8f;              // 薄层
multi_layer.blend_factor = 0.5f;      // 50% 混合
multi_layer.layer_thickness = 0.001f; // 1mm 厚度

// 应用材质
entity->SetMaterial(multi_layer);
scene_->UpdateMaterialsBuffer();  // 更新 GPU 缓冲区
```

### 方法 2：使用辅助函数（更简洁）

在 `Scene` 类中添加辅助方法：

```cpp
// 在 Scene.h 中添加
void ApplyMultiLayerMaterial(int entity_index, 
                             const Material& layer2,
                             float thin = 0.0f,
                             float blend_factor = 0.5f,
                             float layer_thickness = 0.001f);

// 在 Scene.cpp 中实现
void Scene::ApplyMultiLayerMaterial(int entity_index, 
                                     const Material& layer2,
                                     float thin,
                                     float blend_factor,
                                     float layer_thickness) {
    if (entity_index < 0 || entity_index >= entities_.size()) {
        grassland::LogError("Invalid entity index: {}", entity_index);
        return;
    }
    
    auto entity = entities_[entity_index];
    Material multi = entity->GetMaterial();
    
    // 复制所有第二层属性（可以使用宏或循环简化）
    multi.base_color_factor_layer2 = layer2.base_color_factor;
    multi.base_color_tex_layer2 = layer2.base_color_tex;
    // ... 复制所有属性
    
    multi.thin = thin;
    multi.blend_factor = blend_factor;
    multi.layer_thickness = layer_thickness;
    
    entity->SetMaterial(multi);
    UpdateMaterialsBuffer();
}
```

使用方式：
```cpp
scene_->LoadFromGLB("model.glb");
Material layer2 = CreateLayer2Material(...);
scene_->ApplyMultiLayerMaterial(0, layer2, 0.8f, 0.5f, 0.001f);
```

### 方法 3：使用配置文件（JSON）

创建一个 JSON 配置文件定义多层材质：

```json
{
  "multi_layer_materials": [
    {
      "entity_index": 0,
      "layer2": {
        "baseColorFactor": [1.0, 0.2, 0.2, 1.0],
        "baseColorTexture": "textures/paint_basecolor.png",
        "roughnessFactor": 0.1,
        "metallicFactor": 0.9,
        "metallicRoughnessTexture": "textures/paint_metallic_roughness.png",
        "normalTexture": "textures/paint_normal.png",
        "normalScale": 1.0
      },
      "thin": 0.8,
      "blendFactor": 0.5,
      "layerThickness": 0.001
    }
  ]
}
```

然后在代码中加载并应用：
```cpp
// 加载配置
LoadMultiLayerMaterialsFromConfig("materials_config.json");
```

在代码中直接创建多层材质：

```cpp
// 创建第一层材质（底层）
Material layer1(
    glm::vec4(0.8f, 0.8f, 0.9f, 1.0f),  // base color
    base_color_tex_index_1,               // texture index
    0.5f, 0.0f,                           // roughness, metallic
    metallic_roughness_tex_index_1,
    glm::vec3(0.0f),                      // emissive
    emissive_tex_index_1,
    1.0f, ao_tex_index_1,                 // AO
    1.0f, normal_tex_index_1              // normal
);

// 创建第二层材质（外层）
Material layer2(
    glm::vec4(1.0f, 0.2f, 0.2f, 1.0f),   // base color (红色涂层)
    base_color_tex_index_2,
    0.1f, 0.9f,                           // 光滑、金属
    metallic_roughness_tex_index_2,
    glm::vec3(0.0f),
    emissive_tex_index_2,
    1.0f, ao_tex_index_2,
    1.0f, normal_tex_index_2
);

// 组合为多层材质
Material multiLayer = layer1;
// 设置第二层属性
multiLayer.base_color_factor_layer2 = layer2.base_color_factor;
multiLayer.base_color_tex_layer2 = layer2.base_color_tex;
// ... 设置所有第二层属性
multiLayer.thin = 0.8f;              // 薄层
multiLayer.blend_factor = 0.5f;       // 50% 混合
multiLayer.layer_thickness = 0.001f;  // 1mm 厚度
```

## 三、导入到项目

### 步骤 1：放置模型和纹理文件
将模型和纹理文件放到项目的资源目录：
```
ShortMarch/
  assets/
    models/
      your_model.glb          # 主模型（包含第一层材质）
    textures/
      layer2_basecolor.png    # 第二层材质纹理
      layer2_metallic_roughness.png
      layer2_normal.png
```

### 步骤 2：加载模型（只加载第一层材质）
在 `app.cpp` 的 `OnInit()` 中：

```cpp
// 正常加载 glTF 模型（只包含第一层材质）
scene_->LoadFromGLB("assets/models/your_model.glb");
```

### 步骤 3：创建和应用多层材质
在加载模型后，添加代码创建多层材质：

```cpp
// 方法 1：直接创建
Material layer2 = CreateSecondLayerMaterial(...);
auto entity = scene_->GetEntity(0);
Material multi = entity->GetMaterial();
// ... 复制第二层属性并设置控制参数
entity->SetMaterial(multi);
scene_->UpdateMaterialsBuffer();

// 方法 2：使用辅助函数（如果已实现）
scene_->ApplyMultiLayerMaterial(0, layer2, 0.8f, 0.5f, 0.001f);
```

### 步骤 4：验证材质加载
检查日志输出，确认：
- 模型加载成功
- 纹理加载成功
- 多层材质应用成功
- 没有错误信息

## 四、完整示例：绿色铁球 + 铁锈外层

### 4.1 场景描述

创建一个绿色铁球，外面有铁锈的痕迹。这是一个典型的厚层多层材质应用。

### 4.2 准备纹理

确保以下纹理文件在项目中：
```
assets/
  Metal053B_1K-JPG/
    Metal053B_1K-JPG_Color.jpg          # 铁锈颜色
    Metal053B_1K-JPG_Metalness.jpg      # 铁锈金属度
    Metal053B_1K-JPG_Roughness.jpg      # 铁锈粗糙度
    Metal053B_1K-JPG_NormalGL.jpg       # 铁锈法线贴图（OpenGL格式）
```

### 4.3 代码实现

#### 步骤 1：加载纹理到场景

首先需要将纹理加载到场景中，获取纹理索引。需要创建一个辅助函数来加载纹理：

```cpp
// 在 Scene 类中添加辅助方法，或作为独立函数
int LoadTextureFromFile(Scene* scene, const std::string& filepath) {
    // 使用 stb_image 加载图像
    int w, h, comp;
    unsigned char* data = stbi_load(filepath.c_str(), &w, &h, &comp, 4);
    if (!data) {
        grassland::LogError("Failed to load texture: {}", filepath);
        return -1;
    }
    
    // 创建 GPU 纹理
    std::unique_ptr<grassland::graphics::Image> texture;
    scene->GetCore()->CreateImage(w, h, 
                                  grassland::graphics::IMAGE_FORMAT_R8G8B8A8_UNORM, 
                                  &texture);
    texture->UploadData(data);
    
    // 添加到场景并获取索引
    int tex_index = scene->AddTexture(std::move(texture));
    
    stbi_image_free(data);
    return tex_index;
}

// 使用示例（需要传入 core 指针）
// 注意：如果 Scene 类没有 GetCore() 方法，需要添加，或者直接传入 core 指针
int rust_color_tex = LoadTextureFromFile(scene_, core_, 
    "assets/Metal053B_1K-JPG/Metal053B_1K-JPG_Color.jpg");
int rust_metallic_tex = LoadTextureFromFile(scene_, core_,
    "assets/Metal053B_1K-JPG/Metal053B_1K-JPG_Metalness.jpg");
int rust_roughness_tex = LoadTextureFromFile(scene_, core_,
    "assets/Metal053B_1K-JPG/Metal053B_1K-JPG_Roughness.jpg");
int rust_normal_tex = LoadTextureFromFile(scene_, core_,
    "assets/Metal053B_1K-JPG/Metal053B_1K-JPG_NormalGL.jpg");

// 注意：
// 1. 如果 metallic 和 roughness 在同一张纹理中，需要创建组合纹理
// 2. 法线贴图使用 NormalGL（OpenGL 格式）或 NormalDX（DirectX 格式）
// 3. 纹理索引从 0 开始，-1 表示无纹理
// 4. 需要在 Scene 类中添加 GetCore() 方法，或直接传入 core 指针
```

#### 步骤 2：创建绿色铁球（第一层材质）

```cpp
// 创建底层绿色金属材质
Material green_iron(
    glm::vec4(0.0f, 0.8f, 0.2f, 1.0f),  // 绿色 base color
    -1,                                  // 无纹理，使用纯色
    0.3f,                                // roughness: 较光滑
    0.9f,                                // metallic: 高金属度
    -1,                                  // 无 metallic_roughness 纹理
    glm::vec3(0.0f),                     // 无自发光
    -1,                                  // 无自发光纹理
    1.0f,                                // AO strength
    -1,                                  // 无 AO 纹理
    1.0f,                                // normal scale
    -1,                                  // 无法线贴图
    0.0f, 0.0f,                          // clearcoat
    0,                                   // alpha_mode: OPAQUE
    0.0f,                                // transmission: 不透明
    1.45f,                               // ior
    0.0f                                 // dispersion
);
```

#### 步骤 3：创建铁锈外层材质（第二层）

```cpp
// 创建铁锈材质（使用 Metal053B 纹理）
// 注意：由于我们的系统使用 metallic_roughness_tex 同时存储 metallic 和 roughness
// 如果它们是分开的纹理，需要创建一个组合纹理，或者：
// 1. 使用 roughness 纹理作为 metallic_roughness_tex（如果系统支持）
// 2. 创建一个组合纹理，R=metallic, G=roughness

// 方法 1：使用现有纹理（如果系统支持分别的纹理）
Material rust_layer(
    glm::vec4(1.0f, 1.0f, 1.0f, 1.0f),  // base color factor (会被纹理覆盖)
    rust_color_tex,                      // 铁锈颜色纹理
    0.8f,                                // roughness_factor: 高粗糙度（铁锈很粗糙）
    0.3f,                                // metallic_factor: 低金属度（铁锈不是金属）
    rust_roughness_tex,                  // metallic_roughness_tex: 使用 roughness 纹理
                                         // （注意：实际实现中可能需要组合纹理）
    glm::vec3(0.0f),                     // 无自发光
    -1,                                  // 无自发光纹理
    1.0f,                                // AO strength
    -1,                                  // 无 AO 纹理
    1.0f,                                // normal scale
    rust_normal_tex,                     // 铁锈法线贴图（OpenGL 格式）
    0.0f, 0.0f,                          // clearcoat
    0,                                   // alpha_mode: OPAQUE（外层不透明）
    0.0f,                                // transmission: 不透明
    1.45f,                               // ior
    0.0f                                 // dispersion
);

// 方法 2：如果需要组合 metallic 和 roughness 纹理
// 可以创建一个辅助函数来组合纹理
// int combined_tex = CreateCombinedMetallicRoughnessTexture(
//     rust_metallic_tex, rust_roughness_tex);
```

#### 步骤 4：组合为多层材质

```cpp
// 获取球体 Entity（假设是第一个 Entity，或通过名称查找）
auto sphere_entity = scene_->GetEntity(0);  // 或者通过名称查找

// 获取第一层材质（绿色铁）
Material multi_layer = green_iron;

// 复制第二层（铁锈）的所有属性
multi_layer.base_color_factor_layer2 = rust_layer.base_color_factor;
multi_layer.base_color_tex_layer2 = rust_layer.base_color_tex;
multi_layer.roughness_factor_layer2 = rust_layer.roughness_factor;
multi_layer.metallic_factor_layer2 = rust_layer.metallic_factor;
multi_layer.metallic_roughness_tex_layer2 = rust_layer.metallic_roughness_tex;
multi_layer.emissive_factor_layer2 = rust_layer.emissive_factor;
multi_layer.emissive_texture_layer2 = rust_layer.emissive_texture;
multi_layer.AO_strength_layer2 = rust_layer.AO_strength;
multi_layer.AO_texture_layer2 = rust_layer.AO_texture;
multi_layer.normal_scale_layer2 = rust_layer.normal_scale;
multi_layer.normal_texture_layer2 = rust_layer.normal_texture;
multi_layer.clearcoat_factor_layer2 = rust_layer.clearcoat_factor;
multi_layer.clearcoat_roughness_factor_layer2 = rust_layer.clearcoat_roughness_factor;
multi_layer.alpha_mode_layer2 = rust_layer.alpha_mode;
multi_layer.transmission_layer2 = rust_layer.transmission;
multi_layer.ior_layer2 = rust_layer.ior;
multi_layer.dispersion_layer2 = rust_layer.dispersion;

// 设置多层材质控制参数
multi_layer.thin = 0.0f;              // 0.0 = 厚层（外层不透明）
multi_layer.blend_factor = 0.6f;      // 0.6 = 60% 铁锈覆盖，40% 绿色金属露出
multi_layer.layer_thickness = 0.0f;   // 厚层不需要厚度参数

// 应用多层材质
sphere_entity->SetMaterial(multi_layer);
scene_->UpdateMaterialsBuffer();  // 更新 GPU 缓冲区
```

#### 步骤 5：完整代码示例

```cpp
// 辅助函数：加载纹理
// 注意：需要访问 Scene 的 core_，可能需要添加 GetCore() 方法，或直接传入 core
int LoadTextureFromFile(Scene* scene, grassland::graphics::Core* core, const std::string& filepath) {
    int w, h, comp;
    unsigned char* data = stbi_load(filepath.c_str(), &w, &h, &comp, 4);
    if (!data) {
        grassland::LogError("Failed to load texture: {}", filepath);
        return -1;
    }
    
    std::unique_ptr<grassland::graphics::Image> texture;
    core->CreateImage(w, h, 
                      grassland::graphics::IMAGE_FORMAT_R8G8B8A8_UNORM, 
                      &texture);
    texture->UploadData(data);
    
    int tex_index = scene->AddTexture(std::move(texture));
    stbi_image_free(data);
    return tex_index;
}

// 辅助函数：复制第二层属性
void CopyLayer2Properties(Material& multi, const Material& layer2) {
    multi.base_color_factor_layer2 = layer2.base_color_factor;
    multi.base_color_tex_layer2 = layer2.base_color_tex;
    multi.roughness_factor_layer2 = layer2.roughness_factor;
    multi.metallic_factor_layer2 = layer2.metallic_factor;
    multi.metallic_roughness_tex_layer2 = layer2.metallic_roughness_tex;
    multi.emissive_factor_layer2 = layer2.emissive_factor;
    multi.emissive_texture_layer2 = layer2.emissive_texture;
    multi.AO_strength_layer2 = layer2.AO_strength;
    multi.AO_texture_layer2 = layer2.AO_texture;
    multi.normal_scale_layer2 = layer2.normal_scale;
    multi.normal_texture_layer2 = layer2.normal_texture;
    multi.clearcoat_factor_layer2 = layer2.clearcoat_factor;
    multi.clearcoat_roughness_factor_layer2 = layer2.clearcoat_roughness_factor;
    multi.alpha_mode_layer2 = layer2.alpha_mode;
    multi.transmission_layer2 = layer2.transmission;
    multi.ior_layer2 = layer2.ior;
    multi.dispersion_layer2 = layer2.dispersion;
}

// 主函数：创建生锈的绿色铁球
void CreateRustedGreenIronSphere(Scene* scene, grassland::graphics::Core* core) {
    // 1. 加载铁锈纹理（Metal053B_1K-JPG 材质包）
    int rust_color_tex = LoadTextureFromFile(scene, core,
        "assets/Metal053B_1K-JPG/Metal053B_1K-JPG_Color.jpg");
    int rust_metallic_tex = LoadTextureFromFile(scene, core,
        "assets/Metal053B_1K-JPG/Metal053B_1K-JPG_Metalness.jpg");
    int rust_roughness_tex = LoadTextureFromFile(scene, core,
        "assets/Metal053B_1K-JPG/Metal053B_1K-JPG_Roughness.jpg");
    int rust_normal_tex = LoadTextureFromFile(scene, core,
        "assets/Metal053B_1K-JPG/Metal053B_1K-JPG_NormalGL.jpg");
    
    // 2. 创建底层绿色金属材质
    Material green_iron(
        glm::vec4(0.0f, 0.8f, 0.2f, 1.0f),  // 绿色 base color
        -1,                                  // 无纹理，使用纯色
        0.3f,                                // roughness: 较光滑
        0.9f,                                // metallic: 高金属度
        -1,                                  // 无 metallic_roughness 纹理
        glm::vec3(0.0f),                     // 无自发光
        -1,
        1.0f,                                // AO strength
        -1,                                  // 无 AO 纹理
        1.0f,                                // normal scale
        -1,                                  // 无法线贴图
        0.0f, 0.0f,                          // clearcoat
        0,                                   // alpha_mode: OPAQUE
        0.0f,                                // transmission: 不透明
        1.45f,                               // ior
        0.0f                                 // dispersion
    );
    
    // 3. 创建铁锈外层材质（使用 Metal053B 纹理）
    // 注意：这里使用 roughness 纹理作为 metallic_roughness_tex
    // 实际实现中可能需要创建组合纹理
    Material rust_layer(
        glm::vec4(1.0f, 1.0f, 1.0f, 1.0f),  // base color factor（会被纹理覆盖）
        rust_color_tex,                      // 铁锈颜色纹理
        0.8f,                                // roughness_factor: 高粗糙度（铁锈很粗糙）
        0.3f,                                // metallic_factor: 低金属度（铁锈不是金属）
        rust_roughness_tex,                  // metallic_roughness_tex（使用 roughness 纹理）
        glm::vec3(0.0f),                     // 无自发光
        -1,
        1.0f,                                // AO strength
        -1,                                  // 无 AO 纹理
        1.0f,                                // normal scale
        rust_normal_tex,                     // 铁锈法线贴图
        0.0f, 0.0f,                          // clearcoat
        0,                                   // alpha_mode: OPAQUE（外层不透明）
        0.0f,                                // transmission: 不透明
        1.45f,                               // ior
        0.0f                                 // dispersion
    );
    
    // 4. 组合为多层材质
    Material multi_layer = green_iron;
    CopyLayer2Properties(multi_layer, rust_layer);
    
    // 设置多层材质控制参数
    multi_layer.thin = 0.0f;              // 0.0 = 厚层（外层不透明）
    multi_layer.blend_factor = 0.6f;      // 0.6 = 60% 铁锈覆盖，40% 绿色金属露出
    multi_layer.layer_thickness = 0.0f;   // 厚层不需要厚度参数
    
    // 5. 应用到球体 Entity（假设球体是第一个 Entity）
    auto sphere = scene->GetEntity(0);
    if (sphere) {
        sphere->SetMaterial(multi_layer);
        scene->UpdateMaterialsBuffer();  // 更新 GPU 缓冲区
        grassland::LogInfo("Applied multi-layer material to sphere: green iron + rust");
    } else {
        grassland::LogError("Sphere entity not found!");
    }
}
```

**在 app.cpp 中使用**：
```cpp
// 在 OnInit() 中，加载模型后
scene_->LoadFromGLB("assets/models/sphere.glb");  // 加载球体模型
CreateRustedGreenIronSphere(scene_.get(), core_.get());  // 应用多层材质
// 注意：需要传入 core_ 指针用于创建纹理
```

### 4.4 参数调整建议

- **blend_factor = 0.3-0.4**：少量铁锈，大部分是绿色金属（新球）
- **blend_factor = 0.6-0.7**：中等铁锈覆盖（示例值）
- **blend_factor = 0.8-0.9**：大量铁锈，只有少量绿色金属露出（严重锈蚀）

- **roughness_factor_layer2 = 0.7-0.9**：铁锈很粗糙
- **metallic_factor_layer2 = 0.2-0.4**：铁锈不是金属

### 4.5 其他测试示例场景

#### 示例 1：涂漆金属（厚层）
- **第一层**：金属材质（高 metallic，中等 roughness）
- **第二层**：油漆材质（低 metallic，高 roughness）
- **thin**: 0.0（厚层）
- **blend_factor**: 0.3（30% 油漆覆盖）

#### 示例 2：透明涂层（薄层）
- **第一层**：木材材质（低 metallic，高 roughness）
- **第二层**：清漆材质（低 metallic，低 roughness，高 transmission）
- **thin**: 1.0（薄层）
- **blend_factor**: 0.7（70% 清漆效果）
- **layer_thickness**: 0.0005（0.5mm）

#### 示例 3：多层薄膜
- **第一层**：基础塑料
- **第二层**：金属薄膜（高 metallic，低 roughness）
- **thin**: 0.9（很薄的薄膜）
- **blend_factor**: 0.6

## 五、调试技巧

### 1. 检查材质数据
在 `Scene.cpp` 的 `LoadFromGLB()` 中添加日志：
```cpp
grassland::LogInfo("Material {}: thin={}, blend_factor={}", 
                   material_name, mat.thin, mat.blend_factor);
```

### 2. 可视化层分离
临时修改 shader，只渲染第一层或第二层：
```hlsl
// 在 closesthit.hlsl 中
if (mat.thin > 0.5) {
    payload.albedo = payload.albedo_layer2;  // 只显示第二层
} else {
    payload.albedo = payload.albedo;  // 只显示第一层
}
```

### 3. 调整参数
在运行时通过 UI 调整 `thin` 和 `blend_factor` 参数，观察效果变化。

## 六、常见问题

### Q1: 模型没有材质信息怎么办？
**A**: 可以在代码中手动创建材质并应用到 Entity：
```cpp
Material custom_multi_layer = CreateMultiLayerMaterial(...);
entity->SetMaterial(custom_multi_layer);
```

### Q2: 纹理路径不对怎么办？
**A**: 确保纹理文件与 glTF 文件在同一目录，或使用相对路径。

### Q3: 如何知道哪些 Entity 需要多层材质？
**A**: 可以通过以下方式：
- 在代码中硬编码 Entity 索引
- 通过 Entity 名称匹配（如果 glTF 中有名称）
- 通过配置文件指定
- 在 UI 中手动选择并应用

### Q4: 可以混合不同类型的材质吗？
**A**: 可以，但要注意：
- 金属 + 非金属：需要正确设置 metallic 值
- 透明 + 不透明：需要处理 alpha 混合
- 不同 IOR：薄层模式下会有光学效果

## 七、推荐工作流程

1. **准备阶段**：
   - 下载或创建包含材质的模型（glTF 格式）
   - 准备第二层材质的纹理贴图（如果需要）

2. **加载阶段**：
   - 将模型文件放到项目资源目录
   - 在代码中使用 `LoadFromGLB()` 正常加载模型

3. **创建阶段**：
   - 在代码中创建第二层材质对象
   - 设置合理的 `thin`、`blend_factor` 和 `layer_thickness` 值

4. **应用阶段**：
   - 获取需要多层材质的 Entity
   - 将第一层和第二层材质组合
   - 调用 `UpdateMaterialsBuffer()` 更新 GPU 缓冲区

5. **测试阶段**：
   - 运行程序，检查渲染效果
   - 调整参数，优化视觉效果

6. **优化阶段**：
   - 根据性能情况优化 shader 计算
   - 考虑使用辅助函数简化代码

## 八、绿色铁球+铁锈实现总结

### 8.1 实现步骤概览

1. **准备纹理文件**：
   - 将 `Metal053B_1K-JPG` 文件夹放到 `assets/` 目录
   - 确保所有纹理文件可访问

2. **加载纹理**：
   - 使用 `LoadTextureFromFile()` 加载 4 张纹理
   - 获取纹理索引用于材质创建

3. **创建第一层材质（绿色铁球）**：
   - base_color: (0.0, 0.8, 0.2, 1.0) - 绿色
   - metallic: 0.9 - 高金属度
   - roughness: 0.3 - 较光滑
   - 无纹理，使用纯色

4. **创建第二层材质（铁锈）**：
   - 使用 Metal053B 纹理
   - metallic: 0.3 - 低金属度
   - roughness: 0.8 - 高粗糙度
   - 使用法线贴图增强细节

5. **组合多层材质**：
   - thin = 0.0（厚层，外层不透明）
   - blend_factor = 0.6（60% 铁锈覆盖）
   - 复制所有第二层属性到第一层材质

6. **应用到 Entity**：
   - 获取球体 Entity
   - 设置多层材质
   - 更新 GPU 缓冲区

### 8.2 关键参数

| 参数 | 第一层（绿色铁） | 第二层（铁锈） |
|------|----------------|---------------|
| base_color | (0.0, 0.8, 0.2, 1.0) | 纹理：Color.jpg |
| metallic | 0.9 | 0.3 |
| roughness | 0.3 | 0.8 |
| normal | 无 | NormalGL.jpg |
| thin | - | 0.0（厚层） |
| blend_factor | - | 0.6（60%覆盖） |

### 8.3 预期效果

- **视觉效果**：绿色金属球体，表面有铁锈痕迹
- **铁锈分布**：通过 blend_factor 控制，60% 区域显示铁锈
- **细节**：法线贴图提供铁锈的凹凸细节
- **反射**：绿色金属区域保持高反射，铁锈区域较粗糙

### 8.4 如何创建并导入多层材质物体

#### 步骤 1：准备模型
- 下载或创建一个球体模型（glTF 格式）
- 将模型文件放到 `assets/models/` 目录

#### 步骤 2：准备纹理
- 将 `Metal053B_1K-JPG` 文件夹放到 `assets/` 目录
- 确保纹理文件路径正确

#### 步骤 3：在代码中实现
- 参考"四、完整示例：绿色铁球 + 铁锈外层"部分的代码
- 在 `app.cpp` 的 `OnInit()` 中调用 `CreateRustedGreenIronSphere()`

#### 步骤 4：运行和调试
- 运行程序，检查渲染效果
- 调整 `blend_factor` 参数观察不同锈蚀程度
- 检查日志，确保纹理加载成功

## 九、下一步

完成代码实现后，按照以下顺序测试：
1. **单层材质兼容性**：确保 thin=0.0, blend_factor=0.0 时行为与现有系统一致
2. **绿色铁球+铁锈**：测试厚层多层材质的混合效果
3. **参数调整**：调整 blend_factor 观察不同锈蚀程度（0.3, 0.6, 0.9）
4. **薄层材质**：测试薄层材质的光学效果（如果有需要）


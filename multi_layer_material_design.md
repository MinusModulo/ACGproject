# 多层材质（Multi-Layer Material）实现设计文档

## 一、概述

多层材质系统允许在一个表面上叠加两层独立的完整材质，通过 `thin` 参数标识是否为薄层材质，并使用混合参数控制两层材质的混合方式。这对于实现真实世界的材质效果（如涂漆、薄膜、多层涂层等）非常重要。

## 二、设计目标

1. **两层独立材质**：每层材质都拥有完整的 PBR 属性（base_color, roughness, metallic, emission, AO, normal, transmission, ior 等）
2. **薄层标识**：使用 `thin` 参数（0.0-1.0）标识外层材质是否为薄层
3. **混合控制**：使用混合参数控制两层材质的混合方式
4. **向后兼容**：单层材质（thin=0.0, 混合参数=0.0）应该与现有系统完全兼容

## 三、数据结构设计

### 3.1 Material 结构体扩展（C++ 和 HLSL）

需要在现有 Material 结构体基础上添加：

```cpp
// 第二层材质属性（外层材质）
float4 base_color_factor_layer2;
int base_color_tex_layer2;

float roughness_factor_layer2;
float metallic_factor_layer2;
int metallic_roughness_tex_layer2;

float3 emissive_factor_layer2;
int emissive_texture_layer2;

float AO_strength_layer2;
int AO_texture_layer2;

float normal_scale_layer2;
int normal_texture_layer2;

float clearcoat_factor_layer2;
float clearcoat_roughness_factor_layer2;

int alpha_mode_layer2;

float transmission_layer2;
float ior_layer2;
float dispersion_layer2;

// 多层材质控制参数
float thin;              // 0.0 = 厚层（不透明层），1.0 = 薄层（透明层）
float blend_factor;      // 0.0-1.0，控制两层材质的混合强度
float layer_thickness;   // 层厚度（用于薄层的光学计算）
```

### 3.2 RayPayload 扩展

在 `RayPayload` 中添加第二层材质的属性：

```hlsl
// 第二层材质属性
float3 albedo_layer2;
float roughness_layer2;
float metallic_layer2;
float3 emission_layer2;
float ao_layer2;
float clearcoat_layer2;
float clearcoat_roughness_layer2;
float transmission_layer2;
float ior_layer2;
float dispersion_layer2;
int alpha_mode_layer2;
float alpha_layer2;

// 多层材质控制
float thin;
float blend_factor;
float layer_thickness;
```

## 四、实现步骤

### 4.1 数据结构修改

#### 步骤 1：修改 `src/Material.h`
- 在 Material 结构体中添加第二层材质的所有属性
- 更新构造函数，添加默认值
- 确保内存对齐（可能需要调整结构体布局）

#### 步骤 2：修改 `src/shaders/common.hlsl`
- 在 Material 结构体中添加相同的第二层材质属性
- 在 RayPayload 中添加第二层材质属性和控制参数
- 确保与 C++ 结构体完全匹配

### 4.2 Shader 修改

#### 步骤 3：修改 `src/shaders/closesthit.hlsl`
- 在 `ClosestHitMain` 中采样第二层材质的纹理
- 计算第二层材质的最终属性（考虑纹理和因子）
- 将第二层材质属性和控制参数写入 `RayPayload`

#### 步骤 4：修改 `src/shaders/brdf.hlsl`
- 创建新的函数 `eval_brdf_multi_layer()` 用于计算多层材质的 BRDF
- 实现两层材质的混合逻辑：
  - **厚层模式**（thin < 0.5）：两层材质按 blend_factor 线性混合
  - **薄层模式**（thin >= 0.5）：考虑薄层的光学特性，使用能量守恒的混合

#### 步骤 5：修改 `src/shaders/shader.hlsl` (RayGenMain)
- 在路径追踪循环中处理多层材质
- 对于薄层材质，可能需要额外的光线弹射来处理层间交互
- 根据 thin 参数选择不同的材质评估策略

### 4.3 材质加载修改

#### 步骤 6：修改 `src/Scene.cpp`
- 在 `LoadFromGLB()` 中支持加载多层材质
- 支持方式：
  - **方式 A**：通过 glTF 扩展（如自定义扩展 `KHR_materials_multi_layer`）
  - **方式 B**：通过材质命名约定（如 "MaterialName_Layer1" 和 "MaterialName_Layer2"）
  - **方式 C**：通过材质 extras 字段存储第二层材质信息

#### 步骤 7：修改 `src/Scene.cpp` 的 `UpdateMaterialsBuffer()`
- 确保新的 Material 结构体大小正确
- 验证缓冲区大小计算

### 4.4 直接光照修改

#### 步骤 8：修改 `src/shaders/direct_lighting.hlsl`
- 在 `EvaluateLight()` 中使用多层材质的 BRDF
- 确保直接光照计算考虑两层材质

## 五、多层材质混合算法

### 5.1 厚层模式（thin < 0.5）

厚层模式下，两层材质按权重混合：

```hlsl
float3 final_albedo = lerp(albedo_layer1, albedo_layer2, blend_factor);
float final_roughness = lerp(roughness_layer1, roughness_layer2, blend_factor);
float final_metallic = lerp(metallic_layer1, metallic_layer2, blend_factor);
// ... 其他属性类似
```

### 5.2 薄层模式（thin >= 0.5）

薄层模式下，需要考虑光学特性：

1. **能量守恒**：确保反射和透射的能量总和不超过 1.0
2. **层间交互**：光线可能在两层之间多次反射
3. **Fresnel 效应**：考虑不同层的折射率差异

简化实现：
```hlsl
// 计算 Fresnel 项
float F = F_Schlick(ior_layer1, ior_layer2, NdotV);

// 混合两层 BRDF
float3 brdf_layer1 = eval_brdf(...);  // 底层
float3 brdf_layer2 = eval_brdf(...);  // 薄层

// 考虑薄层的透射和反射
float3 final_brdf = brdf_layer1 * (1.0 - F * blend_factor) + 
                    brdf_layer2 * (F * blend_factor);
```

## 六、多层材质创建方案

由于不修改 tinygltf 导入逻辑，我们采用以下方案：

### 方案 A：代码中手动创建（推荐）

在加载模型后，通过代码手动创建和分配多层材质：

```cpp
// 1. 先正常加载 glTF 模型（只加载第一层材质）
scene_->LoadFromGLB("model.glb");

// 2. 获取需要多层材质的 Entity
auto entity = scene_->GetEntity(entity_index);

// 3. 创建第二层材质
Material layer2(
    glm::vec4(1.0f, 0.2f, 0.2f, 1.0f),  // 红色涂层
    layer2_base_color_tex_index,
    0.1f, 0.9f,                          // 光滑、金属
    layer2_metallic_roughness_tex_index,
    glm::vec3(0.0f),
    layer2_emissive_tex_index,
    1.0f, layer2_ao_tex_index,
    1.0f, layer2_normal_tex_index
);

// 4. 获取第一层材质并扩展为多层材质
Material multi_layer = entity->GetMaterial();
// 复制第二层属性
multi_layer.base_color_factor_layer2 = layer2.base_color_factor;
multi_layer.base_color_tex_layer2 = layer2.base_color_tex;
// ... 复制所有第二层属性
multi_layer.thin = 0.8f;
multi_layer.blend_factor = 0.5f;
multi_layer.layer_thickness = 0.001f;

// 5. 应用多层材质
entity->SetMaterial(multi_layer);
scene_->UpdateMaterialsBuffer();  // 更新 GPU 缓冲区
```

### 方案 B：材质配置文件（JSON）

创建一个 JSON 配置文件，定义哪些材质需要多层，以及第二层的属性：

```json
{
  "multi_layer_materials": [
    {
      "entity_name": "PaintedMetal",
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

然后在代码中加载配置并应用：

```cpp
// 加载配置
MultiLayerMaterialConfig config = LoadMultiLayerConfig("materials_config.json");

// 遍历场景中的 Entity，应用多层材质
for (auto& entity : scene_->GetEntities()) {
    if (config.HasMaterial(entity->GetName())) {
        ApplyMultiLayerMaterial(entity, config.GetMaterialConfig(entity->GetName()));
    }
}
```

### 方案 C：材质映射表（最简单）

在代码中维护一个材质映射表，根据 Entity 名称或索引应用多层材质：

```cpp
// 在 Scene 类中添加方法
void Scene::ApplyMultiLayerMaterial(int entity_index, 
                                     const Material& layer2,
                                     float thin, 
                                     float blend_factor,
                                     float layer_thickness) {
    auto entity = entities_[entity_index];
    Material multi = entity->GetMaterial();
    
    // 复制第二层属性
    CopyLayer2Properties(multi, layer2);
    multi.thin = thin;
    multi.blend_factor = blend_factor;
    multi.layer_thickness = layer_thickness;
    
    entity->SetMaterial(multi);
    UpdateMaterialsBuffer();
}
```

### 方案 D：辅助函数创建

提供便捷的辅助函数来创建常见的多层材质组合：

```cpp
// 创建涂漆金属材质
Material CreatePaintedMetalMaterial(
    const Material& base_metal,      // 底层金属
    const glm::vec4& paint_color,    // 油漆颜色
    float paint_roughness,            // 油漆粗糙度
    int paint_texture_index = -1,
    float blend_factor = 0.3f
);

// 创建透明涂层材质
Material CreateClearcoatMaterial(
    const Material& base_material,   // 底层材质
    float clearcoat_roughness,       // 清漆粗糙度
    float clearcoat_thickness,        // 清漆厚度
    float blend_factor = 0.7f
);
```

## 七、文件修改清单

### 需要修改的文件：

1. **`src/Material.h`**
   - 扩展 Material 结构体
   - 更新构造函数

2. **`src/shaders/common.hlsl`**
   - 扩展 Material 和 RayPayload 结构体

3. **`src/shaders/closesthit.hlsl`**
   - 采样第二层材质纹理
   - 计算第二层材质属性

4. **`src/shaders/brdf.hlsl`**
   - 添加 `eval_brdf_multi_layer()` 函数
   - 实现多层材质混合逻辑

5. **`src/shaders/shader.hlsl`**
   - 在路径追踪中处理多层材质
   - 处理薄层的光线交互

6. **`src/shaders/direct_lighting.hlsl`**
   - 使用多层材质 BRDF

7. **`src/Scene.cpp`**
   - 添加 `ApplyMultiLayerMaterial()` 方法用于应用多层材质
   - 添加辅助函数创建常见多层材质组合
   - 更新 `UpdateMaterialsBuffer()` 确保缓冲区大小正确
   - （可选）添加从配置文件加载多层材质的支持

## 八、测试计划

1. **单层材质兼容性测试**：确保 thin=0.0, blend_factor=0.0 时行为与现有系统一致
2. **厚层混合测试**：测试两层厚层材质的混合效果
3. **薄层光学测试**：测试薄层材质的光学特性（反射、透射）
4. **代码创建测试**：测试通过代码手动创建和应用多层材质
5. **配置文件测试**：（如果实现方案 B）测试从配置文件加载多层材质

## 九、注意事项

1. **内存对齐**：确保 C++ 和 HLSL 中的结构体布局一致
2. **性能影响**：多层材质会增加计算量，需要优化
3. **纹理索引**：确保第二层材质的纹理索引正确映射
4. **默认值**：第二层材质的所有属性都应该有合理的默认值
5. **向后兼容**：确保现有单层材质仍然可以正常工作

## 十、实际应用案例

### 案例 1：绿色铁球 + 铁锈外层（厚层材质）

**需求**：内部是绿色的铁球，外面有铁锈的痕迹。

**材质配置**：
- **第一层（底层）**：绿色金属材质
  - base_color: (0.0, 0.8, 0.2, 1.0) - 绿色
  - metallic: 0.9 - 高金属度
  - roughness: 0.3 - 较光滑
  
- **第二层（外层）**：铁锈材质（使用 Metal053B_1K-JPG 材质包）
  - base_color_texture: Metal053B_1K-JPG_Color.jpg
  - metallic_texture: Metal053B_1K-JPG_Metalness.jpg
  - roughness_texture: Metal053B_1K-JPG_Roughness.jpg
  - normal_texture: Metal053B_1K-JPG_NormalGL.jpg
  - metallic_factor: 0.3 - 低金属度（铁锈）
  - roughness_factor: 0.8 - 高粗糙度（铁锈表面粗糙）

- **控制参数**：
  - thin: 0.0 - 厚层（外层不透明）
  - blend_factor: 0.6 - 60% 铁锈覆盖，40% 绿色金属露出
  - layer_thickness: 0.0 - 厚层不需要厚度参数

**实现要点**：
1. **纹理加载**：需要加载 Metal053B_1K-JPG 材质包的所有纹理
   - Color.jpg：铁锈颜色
   - Metalness.jpg：金属度（铁锈低金属度）
   - Roughness.jpg：粗糙度（铁锈高粗糙度）
   - NormalGL.jpg：法线贴图（OpenGL 格式）

2. **混合控制**：
   - 通过 `blend_factor` 控制铁锈的覆盖程度（0.6 = 60% 铁锈）
   - 铁锈纹理的 alpha 通道或遮罩可以进一步控制哪些区域显示铁锈
   - 底层绿色金属在铁锈脱落的地方会显示出来

3. **材质参数**：
   - 第一层（绿色铁）：高金属度(0.9)，低粗糙度(0.3)
   - 第二层（铁锈）：低金属度(0.3)，高粗糙度(0.8)
   - thin = 0.0：厚层，外层不透明

4. **视觉效果**：
   - 使用法线贴图增强铁锈的细节和凹凸感
   - 通过混合因子创建自然的锈蚀效果
   - 绿色金属在铁锈较少的地方会反射光线

## 十一、后续优化方向

1. **更多层支持**：扩展到支持 3 层或更多层
2. **更复杂的光学模型**：实现更精确的薄层光学计算
3. **动态层厚度**：支持基于纹理的层厚度变化
4. **各向异性层**：支持各向异性的薄层材质
5. **遮罩纹理**：支持使用遮罩纹理控制第二层材质的分布


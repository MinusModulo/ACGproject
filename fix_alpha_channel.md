# Alpha 通道透明度修复文档

## 一、问题描述

在场景中，有一个本来应该透明（alpha channel）的物体没有变透明。这个问题可能由以下几个原因导致：

1. **alpha_mode 未正确设置**：材质被设置为 OPAQUE (0)，导致不会进行透明度测试
2. **base_color_factor.a 被设置为 1.0**：即使纹理有 alpha 通道，如果 base_color_factor.a = 1.0，最终 alpha 也会是 1.0
3. **纹理的 alpha 通道未正确加载**：纹理格式不支持 alpha，或加载时丢失了 alpha 通道
4. **glTF 文件中 alphaMode 未设置**：glTF 文件中没有明确设置 alphaMode，导致默认使用 OPAQUE

## 二、Alpha 通道处理流程

### 2.1 数据流

```
glTF 文件
  ↓
Scene.cpp (LoadFromGLB)
  ↓
Material 结构体 (C++)
  ↓
GPU 缓冲区
  ↓
closesthit.hlsl (采样纹理)
  ↓
RayPayload (设置 alpha 和 alpha_mode)
  ↓
shader.hlsl (RayGenMain - alpha 测试)
```

### 2.2 关键代码位置

#### 2.2.1 材质加载（Scene.cpp）

```cpp
// 第 457-464 行：从 glTF 解析 alphaMode
int alphaMode = 0;
if (gm.alphaMode == "MASK") {
    alphaMode = 1;
} else if (gm.alphaMode == "BLEND") {
    alphaMode = 2;
} else {
    alphaMode = 0;  // 默认 OPAQUE
}

// 第 445 行：从 glTF 加载 baseColorFactor
glm::vec4 baseColor = glm::vec4(
    pbrMR.baseColorFactor[0], 
    pbrMR.baseColorFactor[1], 
    pbrMR.baseColorFactor[2], 
    pbrMR.baseColorFactor[3]  // alpha 通道
);
```

#### 2.2.2 纹理采样（closesthit.hlsl）

```68:75:src/shaders/closesthit.hlsl
  float alpha_tex = (mat.base_color_tex >= 0) ? Textures[mat.base_color_tex].SampleLevel(LinearWrap, uv, 0.0f).a : 1.0f;
  float metallic_roughness_tex = (mat.metallic_roughness_tex >= 0) ? Textures[mat.metallic_roughness_tex].SampleLevel(LinearWrap, uv, 0.0f).b : 1.0f;
  float roughness_tex = (mat.metallic_roughness_tex >= 0) ? Textures[mat.metallic_roughness_tex].SampleLevel(LinearWrap, uv, 0.0f).g : 1.0f;
  float3 emissive_tex = (mat.emissive_texture >= 0) ? Textures[mat.emissive_texture].SampleLevel(LinearWrap, uv, 0.0f).rgb : float3(1.0f, 1.0f, 1.0f);
  float AO_tex = (mat.AO_texture >= 0) ? Textures[mat.AO_texture].SampleLevel(LinearWrap, uv, 0.0f).r : 1.0f;

  float3 base_color = mat.base_color_factor.rgb * base_color_tex;
  float alpha = mat.base_color_factor.a * alpha_tex;
```

**关键点**：
- `alpha_tex` 从纹理的 alpha 通道采样（`.a`）
- 如果纹理索引无效（`< 0`），默认 alpha = 1.0
- 最终 alpha = `base_color_factor.a * alpha_tex`

#### 2.2.3 Alpha 测试（shader.hlsl）

```164:179:src/shaders/shader.hlsl
    // alphaMode test :
    if (payload.alpha_mode == 2) { // BLEND
      if (rand(rng_state) > payload.alpha) {
        // skip this intersection, continue tracing
        ray.Origin = payload.position + ray.Direction * payload.new_eps;
        depth += 1;
        continue;
      }
    } else if (payload.alpha_mode == 1) { // MASK
      if (payload.alpha < 0.5) {
        // skip this intersection, continue tracing
        ray.Origin = payload.position + ray.Direction * payload.new_eps;
        depth += 1;
        continue;
      }
    }
```

**关键点**：
- **OPAQUE (0)**：不进行透明度测试，始终渲染
- **MASK (1)**：如果 alpha < 0.5，跳过交点（完全透明）
- **BLEND (2)**：使用随机数进行 alpha 测试（alpha 越大，越可能渲染）

## 三、问题诊断步骤

### 步骤 1：检查 glTF 文件

1. 打开 glTF 文件（JSON 格式）或使用 glTF 查看器
2. 找到有问题的材质，检查：
   - `materials[].alphaMode` 是否设置为 `"MASK"` 或 `"BLEND"`
   - `materials[].pbrMetallicRoughness.baseColorFactor[3]`（alpha 值）是否为 1.0
   - `materials[].pbrMetallicRoughness.baseColorTexture.index` 是否有效

### 步骤 2：检查纹理文件

1. 打开纹理文件（通常是 PNG 或 JPG）
2. 检查纹理是否有 alpha 通道：
   - PNG 支持 alpha 通道
   - JPG 不支持 alpha 通道（alpha 始终为 1.0）
3. 使用图像编辑软件查看 alpha 通道，确认是否有透明区域

### 步骤 3：检查代码中的材质设置

在 `Scene.cpp` 的 `LoadFromGLB()` 函数中，添加调试输出：

```cpp
// 在 Scene.cpp 第 464 行之后添加
grassland::LogInfo("Material alphaMode: {}, baseColor.a: {}", 
                   alphaMode, baseColor.a);
```

### 步骤 4：检查 Shader 中的 alpha 值

在 `closesthit.hlsl` 中添加调试输出（临时）：

```hlsl
// 在 closesthit.hlsl 第 167 行之后添加（临时调试）
if (alpha < 0.99) {
    // 输出 alpha 值（需要转换为颜色输出）
    payload.albedo = float3(alpha, alpha, alpha);  // 临时：用 alpha 值作为颜色
}
```

## 四、修复方案

### 方案 1：在 glTF 文件中设置 alphaMode（推荐）

**适用场景**：可以修改 glTF 文件

**步骤**：
1. 打开 glTF 文件（JSON 格式）
2. 找到需要透明的材质
3. 设置 `alphaMode` 为 `"BLEND"` 或 `"MASK"`：

```json
{
  "materials": [
    {
      "name": "TransparentMaterial",
      "alphaMode": "BLEND",  // 或 "MASK"
      "pbrMetallicRoughness": {
        "baseColorFactor": [1.0, 1.0, 1.0, 0.5],  // alpha = 0.5
        "baseColorTexture": {
          "index": 0
        }
      }
    }
  ]
}
```

**区别**：
- **BLEND**：适合半透明材质（如玻璃、水），使用随机 alpha 测试
- **MASK**：适合有明确透明/不透明区域的材质（如树叶、栅栏），alpha < 0.5 完全透明

### 方案 2：在代码中手动设置 alphaMode

**适用场景**：无法修改 glTF 文件，或需要在运行时动态设置

**步骤**：
1. 在 `Scene.cpp` 的 `LoadFromGLB()` 函数中，加载材质后检查并设置：

```cpp
// 在 Scene.cpp 第 474 行之后添加
// 检查纹理是否有 alpha 通道（简化版本：检查 baseColor.a < 1.0）
if (baseColor.a < 0.99f) {
    // 如果 baseColorFactor 的 alpha < 1.0，自动设置为 BLEND
    alphaMode = 2;
    grassland::LogInfo("Auto-detected transparent material, setting alphaMode to BLEND");
}

// 或者，如果知道特定材质需要透明，可以手动设置：
// if (gm.name == "GlassMaterial" || gm.name == "WaterMaterial") {
//     alphaMode = 2;
// }
```

2. 重新创建 Material 对象：

```cpp
mat = Material(
    baseColor, baseColTexIndex, 
    rough, metallic, metalRoughTexIndex,
    emissive, emissiveTexIndex, 
    aoStrength, aoTexIndex,
    normalScale, normalTexIndex,
    alphaMode,  // 使用更新后的 alphaMode
    0.0f, 1.45f
);
```

### 方案 3：自动检测纹理 alpha 通道（高级）

**适用场景**：需要自动检测纹理是否有透明区域

**步骤**：
1. 在 `Scene.cpp` 中添加函数来检测纹理的 alpha 通道：

```cpp
// 在 Scene.h 中添加声明
bool HasAlphaChannel(int texture_index);

// 在 Scene.cpp 中实现
bool Scene::HasAlphaChannel(int texture_index) {
    // 这里需要访问纹理数据
    // 简化版本：检查纹理格式是否支持 alpha
    // 实际实现需要根据纹理加载方式调整
    // 例如：检查纹理格式是否为 RGBA 或带 alpha 的格式
    return true;  // 占位符，需要实际实现
}
```

2. 在加载材质时使用：

```cpp
// 在 Scene.cpp 第 464 行之后
// 如果纹理有 alpha 通道且 baseColor.a < 1.0，自动设置为 BLEND
if (baseColTexIndex >= 0 && baseColor.a < 0.99f) {
    // 可以进一步检查纹理是否真的有 alpha 通道
    // if (HasAlphaChannel(baseColTexIndex)) {
        alphaMode = 2;  // BLEND
    // }
}
```

### 方案 4：修复 base_color_factor.a

**适用场景**：glTF 文件中的 baseColorFactor[3] 被错误设置为 1.0

**步骤**：
1. 检查 glTF 文件中的 `baseColorFactor[3]`（alpha 值）
2. 如果应该透明但 alpha = 1.0，修改为合适的值（如 0.5 表示半透明）
3. 或者在代码中强制设置：

```cpp
// 在 Scene.cpp 第 445 行之后
// 如果知道特定材质应该透明，可以强制设置 alpha
if (gm.name == "GlassMaterial") {
    baseColor.a = 0.3f;  // 强制设置为半透明
}
```

### 方案 5：修复纹理加载（如果纹理格式不支持 alpha）

**适用场景**：纹理文件有 alpha 通道，但加载时丢失了

**步骤**：
1. 检查纹理加载代码（可能在 `Scene.cpp` 的 `LoadFromGLB()` 或其他地方）
2. 确保纹理以支持 alpha 的格式加载（如 `DXGI_FORMAT_R8G8B8A8_UNORM`）
3. 如果使用 stb_image 加载，确保使用 `stbi_load()` 而不是 `stbi_load_3()`（3 通道不支持 alpha）

## 五、常见问题排查

### 问题 1：alpha_mode 已设置为 BLEND，但仍然不透明

**可能原因**：
- `base_color_factor.a = 1.0` 且纹理 alpha = 1.0，导致最终 alpha = 1.0
- 纹理没有 alpha 通道（如 JPG 格式）

**解决方法**：
1. 检查 `base_color_factor.a` 和纹理的 alpha 通道
2. 确保纹理文件有 alpha 通道（使用 PNG 格式）
3. 在代码中强制设置 `base_color_factor.a < 1.0`

### 问题 2：部分区域透明，部分区域不透明（应该是完全透明）

**可能原因**：
- 使用了 MASK 模式，但 alpha 值在 0.5 附近波动
- 纹理的 alpha 通道有渐变，而不是纯透明/不透明

**解决方法**：
1. 改用 BLEND 模式（更适合渐变透明）
2. 或者预处理纹理，将 alpha < 0.5 的区域设为 0，alpha >= 0.5 的区域设为 1

### 问题 3：透明物体边缘有锯齿

**可能原因**：
- MASK 模式使用硬阈值（0.5），导致边缘不光滑
- 采样数不足，导致 alpha 测试结果不稳定

**解决方法**：
1. 使用 BLEND 模式（更适合平滑透明）
2. 增加采样数（提高渲染质量）
3. 使用更好的 alpha 测试策略（如使用 alpha 值直接混合，而不是随机测试）

## 六、最佳实践

### 1. glTF 文件设置

- **明确设置 alphaMode**：不要依赖默认值
- **使用合适的 alphaMode**：
  - 完全透明/不透明区域 → MASK
  - 半透明材质（玻璃、水） → BLEND
- **确保 baseColorFactor[3] 正确**：如果材质应该透明，alpha 应该 < 1.0

### 2. 纹理文件

- **使用 PNG 格式**：支持 alpha 通道
- **避免 JPG 格式**：不支持 alpha 通道
- **预处理纹理**：确保 alpha 通道正确（透明区域 alpha = 0）

### 3. 代码实现

- **添加自动检测**：如果纹理有 alpha 通道且 baseColor.a < 1.0，自动设置 alphaMode
- **提供手动覆盖**：允许在代码中手动设置 alphaMode（用于特殊材质）
- **添加调试输出**：在开发时输出 alpha 值和 alphaMode，便于诊断

## 七、示例代码

### 示例 1：在 Scene.cpp 中添加自动检测

```cpp
// 在 Scene.cpp 的 LoadFromGLB() 函数中，第 464 行之后添加

// 自动检测透明材质
// 如果 baseColorFactor 的 alpha < 1.0，自动设置为 BLEND
if (baseColor.a < 0.99f && alphaMode == 0) {
    alphaMode = 2;  // BLEND
    grassland::LogInfo("Auto-detected transparent material '{}', setting alphaMode to BLEND (alpha: {})", 
                      gm.name, baseColor.a);
}

// 或者，根据材质名称手动设置
if (gm.name.find("Glass") != std::string::npos || 
    gm.name.find("Water") != std::string::npos ||
    gm.name.find("Transparent") != std::string::npos) {
    alphaMode = 2;  // BLEND
    if (baseColor.a >= 0.99f) {
        baseColor.a = 0.5f;  // 如果 alpha 为 1.0，设置为半透明
    }
}
```

### 示例 2：在运行时修改材质

```cpp
// 在 app.cpp 或 Scene.cpp 中，加载场景后修改材质

// 找到需要透明的实体
for (size_t i = 0; i < scene_->GetEntityCount(); ++i) {
    auto entity = scene_->GetEntity(i);
    Material mat = entity->GetMaterial();
    
    // 检查材质名称或索引
    if (/* 条件：这个实体应该透明 */) {
        // 设置 alphaMode 为 BLEND
        mat.alpha_mode = 2;
        
        // 如果 base_color_factor.a = 1.0，设置为半透明
        if (mat.base_color_factor.a >= 0.99f) {
            mat.base_color_factor.a = 0.5f;
        }
        
        entity->SetMaterial(mat);
    }
}

// 更新 GPU 缓冲区
scene_->UpdateMaterialsBuffer();
```

## 八、验证步骤

修复后，按以下步骤验证：

1. **检查材质设置**：
   - 确认 `alpha_mode` 已正确设置（1 或 2）
   - 确认 `base_color_factor.a` < 1.0（如果需要透明）

2. **检查渲染结果**：
   - 透明区域应该可以看到背后的物体
   - 边缘应该平滑（BLEND 模式）或清晰（MASK 模式）

3. **检查性能**：
   - 透明材质会增加计算开销（alpha 测试）
   - 如果性能下降，考虑减少采样数或使用 MASK 模式

## 九、总结

修复 alpha 通道透明度的关键步骤：

1. **诊断问题**：检查 glTF 文件、纹理文件和代码中的设置
2. **选择方案**：根据情况选择最适合的修复方案
3. **实施修复**：修改 glTF 文件或代码
4. **验证结果**：检查渲染结果和性能

**最常见的解决方案**：
- 在 glTF 文件中设置 `alphaMode: "BLEND"` 或 `"MASK"`
- 确保 `baseColorFactor[3]` < 1.0（如果需要透明）
- 使用支持 alpha 通道的纹理格式（PNG）

**如果问题仍然存在**：
- 检查纹理加载代码，确保 alpha 通道没有被丢失
- 添加调试输出，检查 shader 中的 alpha 值
- 考虑使用更高级的透明度处理（如 alpha 混合而不是 alpha 测试）




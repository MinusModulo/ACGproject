# Shader 模块架构分析文档

## 一、功能概括

`shader.hlsl` 是一个基于 DXR (DirectX Raytracing) 的路径追踪渲染器，已成功模块化为多个独立文件。实现了以下核心功能：

### 1. 路径追踪渲染
- 使用蒙特卡洛方法进行路径追踪
- 支持多级光线弹射（通过俄罗斯轮盘终止）
- 支持渐进式渲染（累积采样）
- 支持像素抖动抗锯齿

### 2. 材质系统
- **PBR 材质**：支持基础颜色、粗糙度、金属度、自发光、AO
- **清漆层（Clearcoat）**：支持清漆效果和清漆粗糙度
- **多层材质**：支持两层材质的混合（Layer 1 基础层 + Layer 2 外层）
  - 厚层模式（Thick Layer）：简单线性混合
  - 薄层模式（Thin Layer）：基于 Fresnel 的能量守恒光学混合
  - 透明度支持：Layer 2 支持 alpha 通道控制透明度
- **透明度**：支持 OPAQUE、MASK、BLEND 三种 alpha 模式
- **透射**：支持折射和色散效果
- **纹理映射**：支持基础颜色、金属度/粗糙度、法线、自发光、AO 纹理
- **UV 生成**：自动处理缺失的 UV 坐标（基于顶点位置生成）

### 3. 光照系统
- **点光源**：支持点光源采样
- **面光源**：支持面光源采样（带面积积分和 PDF 计算）
- **直接光照**：Next Event Estimation (NEE) 直接光照计算
  - 支持单层材质直接光照
  - 支持多层材质直接光照
- **阴影**：通过阴影射线检测遮挡

### 4. BRDF 模型
- **Cook-Torrance 微表面模型**：
  - Fresnel 项（Schlick 近似）
  - 法线分布函数（GGX）
  - 几何遮蔽函数（Smith）
- **单层材质 BRDF**：基础层 + 清漆层的组合
- **多层材质 BRDF**：两层材质的能量守恒混合

### 5. 重要性采样
- **余弦加权半球采样**：用于漫反射
- **GGX 微表面采样**：用于镜面反射
- **多重重要性采样（MIS）**：结合漫反射、镜面反射和清漆层采样
- **多层材质采样**：支持基础层和清漆层的分层采样策略

### 6. 高级特性
- **折射与色散**：支持透明材质的折射和色散效果（RGB 通道分离）
- **法线贴图**：支持切线空间法线贴图
- **抗锯齿**：通过像素抖动实现抗锯齿
- **实体选择**：输出实体 ID 用于交互

---

## 二、文件结构

```
src/shaders/
├── shader.hlsl          # 主文件，包含 RayGenMain 路径追踪主循环
├── common.hlsl          # 数据结构定义和资源绑定
├── rng.hlsl             # 随机数生成模块
├── brdf.hlsl            # BRDF 计算模块（单层 + 多层）
├── sampling.hlsl         # 重要性采样模块
├── light_sampling.hlsl  # 光源采样模块
├── shadow.hlsl          # 阴影检测模块
├── direct_lighting.hlsl # 直接光照计算模块（单层 + 多层）
├── miss.hlsl            # Miss Shader
└── closesthit.hlsl      # Closest Hit Shader
```

---

## 三、模块详细说明

### 1. common.hlsl
**功能**：定义所有数据结构、常量和资源绑定

**包含内容**：
- **数据结构**：
  - `CameraInfo`：相机变换矩阵
  - `Material`：材质属性结构（包含 Layer 1 和 Layer 2 的所有属性）
  - `HoverInfo`：交互信息
  - `Light`：光源信息（点光源和面光源）
  - `Vertex`：顶点信息
  - `RayPayload`：光线载荷数据（包含单层和多层材质属性）
- **常量**：`PI`、`eps`
- **资源绑定**：所有纹理、缓冲区、采样器的绑定

**依赖**：无（基础模块）

**特性**：
- 支持多层材质的数据结构（Layer 1 和 Layer 2）
- 多层材质控制参数：`thin`、`blend_factor`、`layer_thickness`

---

### 2. rng.hlsl
**功能**：提供蒙特卡洛积分所需的随机数生成器

**包含内容**：
- `wang_hash()`：Wang hash 函数（用于初始化随机数状态）
- `rand_xorshift()`：Xorshift 随机数生成器（核心随机数生成）
- `rand()`：归一化随机数生成器（返回 [0, 1) 范围的浮点数）

**依赖**：无

**特性**：
- 使用 Wang Hash + Xorshift 组合，性能高效
- 状态通过 `inout` 参数传递，保证线程安全

---

### 3. brdf.hlsl
**功能**：实现 Cook-Torrance 微表面 BRDF 模型

**包含内容**：
- **基础函数**：
  - `F_Schlick()`：Fresnel 项（Schlick 近似）
  - `D_GGX()`：法线分布函数（GGX）
  - `G_Smith()`：几何遮蔽函数（Smith）
- **单层材质 BRDF**：
  - `eval_brdf()`：完整的单层 BRDF 评估（包括清漆层）
- **多层材质 BRDF**：
  - `eval_brdf_multi_layer()`：多层材质 BRDF 评估
    - 厚层模式：简单线性混合
    - 薄层模式：基于 Fresnel 的能量守恒光学混合
    - 支持 Layer 2 的 alpha 透明度

**依赖**：`common.hlsl`

**特性**：
- 支持单层和多层材质的 BRDF 计算
- 能量守恒的混合算法
- 清漆层支持

---

### 4. sampling.hlsl
**功能**：提供各种重要性采样方法和 PDF 计算

**包含内容**：
- `sample_cosine_hemisphere()`：余弦加权半球采样（用于漫反射）
- `sample_GGX_half()`：GGX 微表面半向量采样（用于镜面反射）
- `pdf_GGX_for_direction()`：GGX 方向的概率密度函数

**依赖**：`common.hlsl`、`brdf.hlsl`

**特性**：
- 支持漫反射和镜面反射的重要性采样
- 提供对应的 PDF 计算用于 MIS

---

### 5. light_sampling.hlsl
**功能**：实现不同类型光源的采样方法

**包含内容**：
- `SamplePointLight()`：点光源采样
  - 计算光源方向
  - 计算距离衰减
  - PDF = 1.0（点光源）
- `SampleAreaLight()`：面光源采样
  - 在光源表面上均匀采样点
  - 计算面积积分
  - 计算正确的 PDF（考虑面积和距离）

**依赖**：`common.hlsl`、`rng.hlsl`

**特性**：
- 支持点光源和面光源
- 面光源采样包含正确的面积积分和 PDF 计算
- 使用随机数生成器进行采样

---

### 6. shadow.hlsl
**功能**：通过阴影射线检测光源遮挡

**包含内容**：
- `CastShadowRay()`：投射阴影射线并检测是否被遮挡
  - 使用 `RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH` 优化性能
  - 使用 `RAY_FLAG_SKIP_CLOSEST_HIT_SHADER` 跳过着色计算

**依赖**：`common.hlsl`

**特性**：
- 高效的阴影检测（只检测是否有遮挡，不计算着色）
- 返回布尔值表示是否被遮挡

---

### 7. direct_lighting.hlsl
**功能**：计算直接光照贡献（Next Event Estimation）

**包含内容**：
- **单层材质直接光照**：
  - `EvaluateLight()`：评估单个光源对单层材质的直接光照贡献
    - 调用光源采样函数
    - 计算 BRDF
    - 执行阴影检测
    - 应用 NEE 权重
- **多层材质直接光照**：
  - `EvaluateLightMultiLayer()`：评估单个光源对多层材质的直接光照贡献
    - 支持厚层和薄层模式
    - 支持 Layer 2 的 alpha 透明度
    - 使用多层材质 BRDF 计算

**依赖**：`common.hlsl`、`light_sampling.hlsl`、`shadow.hlsl`、`brdf.hlsl`

**特性**：
- 支持单层和多层材质的直接光照计算
- 粗糙度钳制（避免光滑表面的火斑）
- 正确的 NEE 权重计算

---

### 8. shader.hlsl
**功能**：主文件，包含 RayGenMain 路径追踪主循环

**包含内容**：
- **模块包含**：按正确顺序包含所有模块
- **RayGenMain()**：路径追踪主循环
  - 相机射线生成（带像素抖动抗锯齿）
  - 路径追踪循环
  - 透射处理（折射/反射，支持色散）
  - Alpha 测试（OPAQUE、MASK、BLEND）
  - 重要性采样方向选择（支持多层材质采样策略）
  - 多层材质 BRDF 评估
  - 俄罗斯轮盘终止
  - 结果累积（渐进式渲染）

**依赖**：所有其他模块

**特性**：
- 支持多层材质的路径追踪
- 支持透射和色散
- 支持渐进式渲染
- 支持实体选择输出

---

### 9. miss.hlsl
**功能**：Miss Shader 入口点，处理未命中场景的光线

**包含内容**：
- `MissMain()`：设置未命中标志

**依赖**：`common.hlsl`

**特性**：
- 简单的未命中处理（在 RayGenMain 中处理天空颜色）

---

### 10. closesthit.hlsl
**功能**：Closest Hit Shader 入口点，处理光线与几何体的最近交点

**包含内容**：
- `ClosestHitMain()`：
  - 材质索引获取
  - 顶点数据插值
  - UV 坐标处理（自动生成缺失的 UV）
  - 纹理采样（Layer 1 和 Layer 2）
  - 法线计算（几何法线/插值法线/法线贴图）
  - 材质属性计算（Layer 1 和 Layer 2）
  - 直接光照计算（根据材质类型选择单层或多层）

**依赖**：`common.hlsl`、`direct_lighting.hlsl`

**特性**：
- 支持多层材质的纹理采样和属性计算
- 自动处理缺失的 UV 坐标
- 根据 `blend_factor` 自动选择单层或多层直接光照计算
- 支持法线贴图

---

## 四、模块依赖关系

```
common.hlsl (基础结构)
    │
    ├── rng.hlsl (随机数生成)
    │   └── light_sampling.hlsl (光源采样)
    │
    ├── brdf.hlsl (BRDF 计算)
    │   └── sampling.hlsl (重要性采样)
    │       └── brdf.hlsl (循环依赖，但通过前向声明解决)
    │
    ├── shadow.hlsl (阴影检测)
    │
    └── direct_lighting.hlsl (直接光照)
        ├── light_sampling.hlsl
        ├── shadow.hlsl
        └── brdf.hlsl
            │
            └── closesthit.hlsl (交点处理)
                └── direct_lighting.hlsl (循环依赖，但通过 include 顺序解决)
                    │
                    └── shader.hlsl (主循环)
                        └── miss.hlsl (未命中处理)
```

**依赖说明**：
- `common.hlsl` 是所有模块的基础
- `rng.hlsl` 被 `light_sampling.hlsl` 使用
- `brdf.hlsl` 被 `sampling.hlsl` 和 `direct_lighting.hlsl` 使用
- `sampling.hlsl` 使用 `brdf.hlsl` 中的 `D_GGX()` 函数
- `direct_lighting.hlsl` 整合了光源采样、阴影检测和 BRDF 计算
- `closesthit.hlsl` 使用 `direct_lighting.hlsl` 进行直接光照计算
- `shader.hlsl` 作为主文件包含所有模块

---

## 五、多层材质系统

### 5.1 数据结构

多层材质在 `Material` 和 `RayPayload` 结构中包含以下字段：

**Layer 1 (基础层)**：
- `base_color_factor` / `base_color_tex`
- `roughness_factor` / `metallic_factor` / `metallic_roughness_tex`
- `emissive_factor` / `emissive_texture`
- `AO_strength` / `AO_texture`
- `normal_scale` / `normal_texture`
- `clearcoat_factor` / `clearcoat_roughness_factor`
- `alpha_mode` / `transmission` / `ior` / `dispersion`

**Layer 2 (外层)**：
- 所有 Layer 1 的对应字段，后缀为 `_layer2`

**控制参数**：
- `thin`：0.0 = 厚层模式，1.0 = 薄层模式
- `blend_factor`：0.0-1.0，控制两层材质的混合强度
- `layer_thickness`：层厚度（用于薄层的光学计算）

### 5.2 BRDF 评估

多层材质的 BRDF 评估在 `eval_brdf_multi_layer()` 中实现：

**厚层模式** (`thin < 0.5`)：
- 简单线性混合：`lerp(brdf_layer1, brdf_layer2, effective_blend)`
- `effective_blend = blend_factor * alpha_layer2`（考虑透明度）

**薄层模式** (`thin >= 0.5`)：
- 基于 Fresnel 的能量守恒光学混合
- 外层反射 + 内层透射
- 考虑透明度：`transmission_factor = 1.0 - F * effective_blend`

### 5.3 直接光照

多层材质的直接光照在 `EvaluateLightMultiLayer()` 中实现：
- 使用多层材质 BRDF 计算
- 支持 Layer 2 的 alpha 透明度
- 根据 `blend_factor` 自动选择单层或多层计算

### 5.4 路径追踪

在 `RayGenMain()` 中：
- 根据 `payload.blend_factor > 0.0` 判断是否使用多层材质
- 使用 `eval_brdf_multi_layer()` 进行 BRDF 评估
- 支持多层材质的采样策略（基础层 + 清漆层）

---

## 六、编译和包含顺序

主文件 `shader.hlsl` 的包含顺序：

```hlsl
#include "common.hlsl"
#include "rng.hlsl"
#include "brdf.hlsl"
#include "sampling.hlsl"
#include "light_sampling.hlsl"
#include "shadow.hlsl"
#include "direct_lighting.hlsl"
// ... RayGenMain 函数 ...
#include "miss.hlsl"
#include "closesthit.hlsl"
```

**注意事项**：
1. 所有模块使用 `#ifndef` 和 `#define` 防止重复包含
2. 资源绑定统一在 `common.hlsl` 中管理
3. 模块间的依赖关系通过 include 顺序保证
4. HLSL 编译器会按照 include 顺序处理所有模块

---

## 七、优势

1. **模块化**：代码按功能清晰分离，易于维护
2. **可重用性**：模块可以在其他着色器中重用
3. **可读性**：代码结构清晰，易于理解
4. **可扩展性**：易于添加新功能（如新的 BRDF 模型、新的光源类型）
5. **多层材质支持**：完整的双层材质系统，支持厚层和薄层模式
6. **向后兼容**：单层材质代码仍然可用（`blend_factor = 0` 时）

---

## 八、未来改进方向

1. **更多层支持**：扩展到三层或更多层材质
2. **更复杂的薄层模型**：考虑实际的光学物理（如薄膜干涉）
3. **体积渲染**：支持参与介质和体积散射
4. **更高级的采样策略**：如 Metropolis Light Transport (MLT)
5. **GPU 加速的纹理压缩**：优化纹理采样性能
6. **自适应采样**：根据场景复杂度动态调整采样数

---

## 九、注意事项

1. **依赖管理**：模块化时需要正确处理 `#include` 顺序
2. **资源绑定**：所有资源绑定应在 `common.hlsl` 中统一管理
3. **函数声明**：某些函数有前向声明（如 `eval_brdf`），需要处理
4. **常量定义**：`PI` 和 `eps` 等常量应在 `common.hlsl` 中定义
5. **编译顺序**：HLSL 编译器需要正确的包含顺序
6. **多层材质性能**：多层材质会增加计算开销，需要权衡质量和性能
7. **透明度处理**：Layer 2 的 alpha 透明度会影响混合结果，需要正确设置

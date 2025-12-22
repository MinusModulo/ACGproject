# Shader.hlsl 功能概括与模块划分

## 一、功能概括

`shader.hlsl` 是一个基于 DXR (DirectX Raytracing) 的路径追踪渲染器，实现了以下核心功能：

### 1. 路径追踪渲染
- 使用蒙特卡洛方法进行路径追踪
- 支持多级光线弹射（通过俄罗斯轮盘终止）
- 支持渐进式渲染（累积采样）

### 2. 材质系统
- **PBR 材质**：支持基础颜色、粗糙度、金属度、自发光、AO
- **清漆层（Clearcoat）**：支持清漆效果和清漆粗糙度
- **透明度**：支持 OPAQUE、MASK、BLEND 三种 alpha 模式
- **透射**：支持折射和色散效果
- **纹理映射**：支持基础颜色、金属度/粗糙度、法线、自发光、AO 纹理

### 3. 光照系统
- **点光源**：支持点光源采样
- **面光源**：支持面光源采样（带面积积分）
- **直接光照**：Next Event Estimation (NEE) 直接光照计算
- **阴影**：通过阴影射线检测遮挡

### 4. BRDF 模型
- **Cook-Torrance 微表面模型**：
  - Fresnel 项（Schlick 近似）
  - 法线分布函数（GGX）
  - 几何遮蔽函数（Smith）
- **多层材质**：基础层 + 清漆层的组合

### 5. 重要性采样
- **余弦加权半球采样**：用于漫反射
- **GGX 微表面采样**：用于镜面反射
- **多重重要性采样（MIS）**：结合漫反射和镜面反射采样

### 6. 高级特性
- **折射与色散**：支持透明材质的折射和色散效果
- **法线贴图**：支持切线空间法线贴图
- **抗锯齿**：通过像素抖动实现抗锯齿
- **实体选择**：输出实体 ID 用于交互

---

## 二、模块划分

根据功能，可以将 `shader.hlsl` 划分为以下模块：

### 模块 1: 数据结构定义 (Lines 1-108)
**功能**：定义所有数据结构和资源绑定

**包含内容**：
- `CameraInfo`：相机变换矩阵
- `Material`：材质属性结构
- `HoverInfo`：交互信息
- `Light`：光源信息
- `Vertex`：顶点信息
- `RayPayload`：光线载荷数据
- 所有资源绑定（纹理、缓冲区、采样器等）

**建议文件名**：`common.hlsl` 或 `structures.hlsl`

---

### 模块 2: 随机数生成 (Lines 114-132)
**功能**：提供蒙特卡洛积分所需的随机数生成器

**包含内容**：
- `wang_hash()`：Wang hash 函数
- `rand_xorshift()`：Xorshift 随机数生成器
- `rand()`：归一化随机数生成器

**建议文件名**：`rng.hlsl`

---

### 模块 3: 光源采样 (Lines 135-158)
**功能**：实现不同类型光源的采样方法

**包含内容**：
- `SamplePointLight()`：点光源采样
- `SampleAreaLight()`：面光源采样（带面积积分和 PDF 计算）

**建议文件名**：`light_sampling.hlsl`

---

### 模块 4: 阴影检测 (Lines 163-185)
**功能**：通过阴影射线检测光源遮挡

**包含内容**：
- `CastShadowRay()`：投射阴影射线并检测是否被遮挡
- `dead()`：辅助函数（似乎未使用）

**建议文件名**：`shadow.hlsl`

---

### 模块 5: BRDF 计算 (Lines 196-282)
**功能**：实现 Cook-Torrance 微表面 BRDF 模型

**包含内容**：
- `F_Schlick()`：Fresnel 项（Schlick 近似）
- `D_GGX()`：法线分布函数（GGX）
- `G_Smith()`：几何遮蔽函数（Smith）
- `eval_brdf()`：完整的 BRDF 评估（包括清漆层）

**建议文件名**：`brdf.hlsl`

---

### 模块 6: 重要性采样 (Lines 285-312)
**功能**：提供各种采样方法和 PDF 计算

**包含内容**：
- `sample_cosine_hemisphere()`：余弦加权半球采样
- `sample_GGX_half()`：GGX 微表面半向量采样
- `pdf_GGX_for_direction()`：GGX 方向的概率密度函数

**建议文件名**：`sampling.hlsl`

---

### 模块 7: 直接光照计算 (Lines 198-224)
**功能**：计算直接光照贡献（Next Event Estimation）

**包含内容**：
- `EvaluateLight()`：评估单个光源的直接光照贡献
  - 调用光源采样函数
  - 计算 BRDF
  - 执行阴影检测
  - 应用 NEE 权重

**建议文件名**：`direct_lighting.hlsl`

---

### 模块 8: 光线生成主函数 (Lines 314-585)
**功能**：路径追踪的主循环

**包含内容**：
- `RayGenMain()`：光线生成和路径追踪主循环
  - 相机射线生成
  - 路径追踪循环
  - 透射处理（折射/反射）
  - Alpha 测试
  - 重要性采样方向选择
  - 俄罗斯轮盘终止
  - 结果累积

**建议文件名**：`raygen.hlsl`（保留在主文件或单独文件）

---

### 模块 9: Miss Shader (Lines 587-589)
**功能**：处理未命中场景的光线

**包含内容**：
- `MissMain()`：设置未命中标志

**建议文件名**：`miss.hlsl`

---

### 模块 10: Closest Hit Shader (Lines 591-712)
**功能**：处理光线与几何体的最近交点

**包含内容**：
- `ClosestHitMain()`：
  - 材质索引获取
  - 顶点数据插值
  - 纹理采样
  - 法线计算（几何法线/插值法线/法线贴图）
  - 材质属性计算
  - 直接光照计算

**建议文件名**：`closesthit.hlsl`

---

## 三、模块依赖关系

```
common.hlsl (基础结构)
    ↓
rng.hlsl (随机数生成)
    ↓
light_sampling.hlsl (光源采样) ──┐
    ↓                              │
shadow.hlsl (阴影检测)             │
    ↓                              │
brdf.hlsl (BRDF 计算)              │
    ↓                              │
sampling.hlsl (重要性采样)         │
    ↓                              │
direct_lighting.hlsl (直接光照) ←──┘
    ↓
raygen.hlsl (主循环)
    ↓
miss.hlsl (未命中处理)
    ↓
closesthit.hlsl (交点处理)
```

---

## 四、重构建议

### 方案 1：完全模块化
将所有模块拆分为独立文件，主文件只包含入口函数和必要的包含。

### 方案 2：部分模块化
将工具函数（RNG、采样、BRDF）拆分为独立模块，保留主循环在主文件中。

### 方案 3：功能分组
- **核心模块**：common.hlsl, raygen.hlsl, closesthit.hlsl, miss.hlsl
- **工具模块**：rng.hlsl, brdf.hlsl, sampling.hlsl
- **光照模块**：light_sampling.hlsl, shadow.hlsl, direct_lighting.hlsl

---

## 五、注意事项

1. **依赖管理**：模块化时需要正确处理 `#include` 顺序
2. **资源绑定**：所有资源绑定应在 `common.hlsl` 中统一管理
3. **函数声明**：某些函数有前向声明（如 `eval_brdf`），需要处理
4. **常量定义**：`PI` 和 `eps` 等常量应在 `common.hlsl` 中定义
5. **编译顺序**：HLSL 编译器需要正确的包含顺序


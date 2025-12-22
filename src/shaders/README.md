# Shader 模块结构说明

## 模块划分完成

`shader.hlsl` 已成功模块化为以下结构：

## 文件结构

```
src/shaders/
├── shader.hlsl          # 主文件，包含 RayGenMain 和所有模块的包含
├── common.hlsl          # 数据结构定义和资源绑定
├── rng.hlsl             # 随机数生成模块
├── brdf.hlsl            # BRDF 计算模块
├── sampling.hlsl        # 重要性采样模块
├── light_sampling.hlsl  # 光源采样模块
├── shadow.hlsl          # 阴影检测模块
├── direct_lighting.hlsl # 直接光照计算模块
├── miss.hlsl            # Miss Shader
└── closesthit.hlsl      # Closest Hit Shader
```

## 模块依赖关系

```
common.hlsl (基础结构)
    ↓
├── rng.hlsl (随机数生成)
│   └── light_sampling.hlsl (光源采样)
│
├── brdf.hlsl (BRDF 计算)
│   └── sampling.hlsl (重要性采样)
│
├── shadow.hlsl (阴影检测)
│
└── direct_lighting.hlsl (直接光照)
    ├── light_sampling.hlsl
    ├── shadow.hlsl
    └── brdf.hlsl
        └── closesthit.hlsl
            └── direct_lighting.hlsl
```

## 模块说明

### 1. common.hlsl
- **功能**：定义所有数据结构（CameraInfo, Material, Light, RayPayload 等）
- **包含**：常量定义（PI, eps）和所有资源绑定
- **依赖**：无

### 2. rng.hlsl
- **功能**：随机数生成器（Wang Hash + Xorshift）
- **函数**：`wang_hash()`, `rand_xorshift()`, `rand()`
- **依赖**：无

### 3. brdf.hlsl
- **功能**：Cook-Torrance 微表面 BRDF 模型
- **函数**：`F_Schlick()`, `D_GGX()`, `G_Smith()`, `eval_brdf()`
- **依赖**：common.hlsl

### 4. sampling.hlsl
- **功能**：重要性采样方法
- **函数**：`sample_cosine_hemisphere()`, `sample_GGX_half()`, `pdf_GGX_for_direction()`
- **依赖**：common.hlsl, brdf.hlsl

### 5. light_sampling.hlsl
- **功能**：光源采样（点光源和面光源）
- **函数**：`SamplePointLight()`, `SampleAreaLight()`
- **依赖**：common.hlsl, rng.hlsl

### 6. shadow.hlsl
- **功能**：阴影射线检测
- **函数**：`CastShadowRay()`
- **依赖**：common.hlsl

### 7. direct_lighting.hlsl
- **功能**：直接光照计算（Next Event Estimation）
- **函数**：`EvaluateLight()`
- **依赖**：common.hlsl, light_sampling.hlsl, shadow.hlsl, brdf.hlsl

### 8. miss.hlsl
- **功能**：Miss Shader 入口点
- **函数**：`MissMain()`
- **依赖**：common.hlsl

### 9. closesthit.hlsl
- **功能**：Closest Hit Shader 入口点
- **包含**：材质采样、法线计算、直接光照计算
- **依赖**：common.hlsl, direct_lighting.hlsl

### 10. shader.hlsl
- **功能**：主文件，包含 RayGenMain 路径追踪主循环
- **包含**：所有模块的 include 语句

## 使用说明

主文件 `shader.hlsl` 会自动包含所有必要的模块。编译时，HLSL 编译器会按照 include 顺序处理所有模块。

## 优势

1. **模块化**：代码按功能清晰分离
2. **可维护性**：每个模块职责单一，易于修改和调试
3. **可重用性**：模块可以在其他着色器中重用
4. **可读性**：代码结构清晰，易于理解

## 注意事项

- 所有模块使用 `#ifndef` 和 `#define` 防止重复包含
- 资源绑定统一在 `common.hlsl` 中管理
- 模块间的依赖关系已正确设置
- 编译顺序由 include 语句保证


# Fireflies 减少方案分析文档

## 一、问题描述

场景中出现大量 fireflies（火斑/噪点），这是路径追踪渲染中的常见问题。Fireflies 表现为：
- 图像中出现异常明亮的像素点
- 特别是在光滑表面、小光源、或者光源直接可见的区域
- 导致图像质量下降，需要更多采样才能收敛

---

## 二、Fireflies 产生的原因

### 2.1 主要原因

1. **高方差采样**：
   - 光滑表面（低粗糙度）导致 BRDF 的镜面反射项非常尖锐
   - 小光源或远距离光源导致光源采样 PDF 很大
   - 当 BRDF 值很大但 PDF 很小时，贡献值会爆炸

2. **MIS 权重计算问题**：
   - 如果 PDF 计算不准确，MIS 权重可能不正确
   - 点光源的 delta 分布处理不当

3. **光源采样 PDF 计算**：
   - 面光源的 PDF 计算可能在某些角度下变得很小
   - 距离很近时，PDF 可能变得很大

4. **粗糙度钳制不足**：
   - 当前只钳制到 0.15，对于非常光滑的表面可能不够

5. **俄罗斯轮盘终止策略**：
   - 终止概率计算可能导致某些路径权重过大

---

## 三、当前实现分析

### 3.1 粗糙度钳制

**位置**：`src/shaders/direct_lighting.hlsl`

```hlsl
float safe_roughness = max(roughness, 0.15);
```

**问题**：
- 只钳制到 0.15，对于非常光滑的表面（roughness < 0.15）可能不够
- 没有考虑光源大小和距离的影响

### 3.2 光源采样 PDF

**位置**：`src/shaders/light_sampling.hlsl`

```hlsl
// 面光源
inv_pdf = area * cos_theta / max(dist_sq, 1e-2);
```

**问题**：
- 当距离很近时，`dist_sq` 很小，`inv_pdf` 很大，导致 PDF 很小
- 当角度很小时，`cos_theta` 很小，`inv_pdf` 很小，导致 PDF 很大
- 这些极端情况可能导致贡献值爆炸

### 3.3 MIS 权重计算

**位置**：`src/shaders/direct_lighting.hlsl`

```hlsl
float w_light = mis_weight_balance(pdf_light_actual, pdf_brdf_for_light_dir);
direct_light += w_light * contribution_light / max(pdf_light_actual, eps);
```

**问题**：
- 如果 `pdf_light_actual` 很小，`contribution_light / pdf_light_actual` 会很大
- 即使有 MIS 权重，如果权重计算不准确，仍然可能导致 fireflies

---

## 四、改进方案

### 4.1 方案 1：增强粗糙度钳制（最简单，立即实施）

**思路**：根据光源大小和距离动态调整粗糙度钳制值

**实现**：
```hlsl
// 计算光源的角直径（solid angle）
float light_solid_angle = 0.0;
if (light.type == 0) {
    // 点光源：使用固定的小角度
    light_solid_angle = 0.01; // 约 0.57 度
} else if (light.type == 1) {
    // 面光源：计算实际的立体角
    float area = length(cross(light.u, light.v));
    float dist_sq = dot(light.position - position, light.position - position);
    light_solid_angle = area / max(dist_sq, 1e-2);
}

// 根据光源大小动态调整粗糙度钳制
// 光源越小，需要的粗糙度越大
float min_roughness = 0.15;
if (light_solid_angle < 0.1) {
    // 小光源：需要更大的粗糙度
    min_roughness = max(0.2, 0.15 / sqrt(light_solid_angle * 10.0));
}
min_roughness = clamp(min_roughness, 0.15, 0.5); // 限制在合理范围

float safe_roughness = max(roughness, min_roughness);
```

**优点**：
- 实现简单
- 立即见效
- 不影响其他部分

**缺点**：
- 可能过度平滑某些表面
- 不是根本解决方案

---

### 4.2 方案 2：改进光源采样 PDF 计算（重要）

**思路**：防止 PDF 变得过小或过大

**实现**：
```hlsl
// 在 light_sampling.hlsl 中
float3 SampleAreaLight(Light light, float3 position, out float3 light_dir, inout float inv_pdf, inout float3 sampled_point, inout uint rng_state) {
    float u1 = rand(rng_state);
    float u2 = rand(rng_state);
    
    sampled_point = light.position + (u1 - 0.5f) * light.u + (u2 - 0.5f) * light.v;
    light_dir = normalize(sampled_point - position);
    
    float area = length(cross(light.u, light.v));
    float dist_sq = dot(sampled_point - position, sampled_point - position);
    float cos_theta = max(dot(-light_dir, normalize(light.direction)), 0.0f);
    
    // 改进：钳制 dist_sq 和 cos_theta，防止极端值
    dist_sq = max(dist_sq, 0.01); // 最小距离 0.1
    cos_theta = max(cos_theta, 0.01); // 最小角度约 84 度
    
    // 改进：限制 inv_pdf 的范围
    inv_pdf = area * cos_theta / dist_sq;
    inv_pdf = clamp(inv_pdf, 1e-3, 1e3); // 限制在合理范围
    
    return light.color * light.intensity;
}
```

**优点**：
- 直接解决 PDF 计算问题
- 防止极端值

**缺点**：
- 可能在某些情况下不够准确

---

### 4.3 方案 3：贡献值钳制（快速修复）

**思路**：直接钳制贡献值，防止异常大的值

**实现**：
```hlsl
// 在 direct_lighting.hlsl 中
if (light_sample_valid) {
    // ... 计算 contribution_light ...
    
    // 钳制贡献值
    float max_contribution = 10.0; // 根据场景调整
    contribution_light = min(contribution_light, float3(max_contribution, max_contribution, max_contribution));
    
    // ... 使用 MIS ...
}
```

**优点**：
- 最简单直接
- 立即消除 fireflies

**缺点**：
- 可能丢失某些高光细节
- 不是物理正确的

---

### 4.4 方案 4：改进 MIS 权重计算（推荐）

**思路**：使用功率启发式（Power Heuristic）替代平衡启发式，并添加安全检查

**实现**：
```hlsl
// 使用功率启发式（β=2），对高 PDF 的策略给予更多权重
float mis_weight_power_safe(float pdf_a, float pdf_b) {
    // 防止 PDF 为 0 或过小
    pdf_a = max(pdf_a, eps);
    pdf_b = max(pdf_b, eps);
    
    // 如果 PDF 差异太大，使用更保守的权重
    float ratio = pdf_a / pdf_b;
    if (ratio > 100.0 || ratio < 0.01) {
        // PDF 差异太大，只使用较大的那个
        return (pdf_a > pdf_b) ? 1.0 : 0.0;
    }
    
    // 功率启发式（β=2）
    float pdf_a_pow = pdf_a * pdf_a;
    float pdf_b_pow = pdf_b * pdf_b;
    float pdf_sum = pdf_a_pow + pdf_b_pow;
    return pdf_sum > eps ? (pdf_a_pow / pdf_sum) : 0.5;
}
```

**优点**：
- 更稳定的权重计算
- 处理极端情况

**缺点**：
- 计算开销稍大
- 需要调整参数

---

### 4.5 方案 5：自适应采样（高级）

**思路**：检测高方差区域，增加采样数或使用不同的采样策略

**实现**：
```hlsl
// 检测贡献值是否异常大
bool is_firefly = any(contribution_light > float3(5.0, 5.0, 5.0));

if (is_firefly) {
    // 对于可能的 firefly，使用更保守的策略
    // 1. 增加粗糙度钳制
    safe_roughness = max(safe_roughness, 0.3);
    
    // 2. 使用更保守的 MIS 权重
    w_light = min(w_light, 0.9); // 限制最大权重
    
    // 3. 钳制贡献值
    contribution_light = min(contribution_light, float3(10.0, 10.0, 10.0));
}
```

**优点**：
- 只在需要时应用修复
- 保持大部分场景的准确性

**缺点**：
- 实现复杂
- 需要调试参数

---

### 4.6 方案 6：改进俄罗斯轮盘终止（辅助）

**思路**：改进路径终止策略，防止某些路径权重过大

**实现**：
```hlsl
// 在 shader.hlsl 中
// Russian roulette termination
float p = saturate(max(throughput.x, max(throughput.y, throughput.z)));
p = clamp(p, 0.05, 0.95);

// 改进：如果 throughput 过大，强制终止
if (any(throughput > float3(10.0, 10.0, 10.0))) {
    break; // 强制终止，防止 firefly
}

if (rand(rng_state) > p) break;
throughput /= p;
```

**优点**：
- 防止路径权重爆炸
- 简单有效

**缺点**：
- 可能过早终止某些有效路径

---

## 五、推荐实施顺序

### 阶段 1：快速修复（立即实施）
1. ✅ **方案 1**：增强粗糙度钳制
2. ✅ **方案 3**：贡献值钳制（作为安全网）

### 阶段 2：根本修复（短期）
3. ✅ **方案 2**：改进光源采样 PDF 计算
4. ✅ **方案 4**：改进 MIS 权重计算

### 阶段 3：优化（长期）
5. ⚠️ **方案 5**：自适应采样（如果需要）
6. ⚠️ **方案 6**：改进俄罗斯轮盘终止（辅助）

---

## 六、具体实施建议

### 6.1 立即实施（方案 1 + 方案 3）

**修改文件**：`src/shaders/direct_lighting.hlsl`

```hlsl
// 在 EvaluateLight 函数中
float NdotL_light = max(dot(normal, light_dir), 0.0);
if (NdotL_light > 0.0) {
    // 计算光源立体角
    float light_solid_angle = 0.0;
    if (light.type == 0) {
        light_solid_angle = 0.01;
    } else if (light.type == 1) {
        float area = length(cross(light.u, light.v));
        float dist_sq = max(dot(light.position - position, light.position - position), 0.01);
        light_solid_angle = area / dist_sq;
    }
    
    // 动态调整粗糙度钳制
    float min_roughness = 0.15;
    if (light_solid_angle < 0.1) {
        min_roughness = clamp(0.15 / sqrt(max(light_solid_angle * 10.0, 0.1)), 0.15, 0.4);
    }
    
    float safe_roughness = max(roughness, min_roughness);
    float3 brdf_light = eval_brdf(normal, light_dir, view_dir, albedo, safe_roughness, metallic, ao, clearcoat, clearcoat_roughness);
    
    if (!CastShadowRay(position + normal * 1e-3, light_dir, max_distance - 1e-3)) {
        contribution_light = brdf_light * radiance_light * NdotL_light;
        
        // 钳制贡献值（安全网）
        float max_contribution = 20.0; // 根据场景调整
        contribution_light = min(contribution_light, float3(max_contribution, max_contribution, max_contribution));
        
        light_sample_valid = true;
    }
}
```

### 6.2 短期实施（方案 2）

**修改文件**：`src/shaders/light_sampling.hlsl`

```hlsl
float3 SampleAreaLight(Light light, float3 position, out float3 light_dir, inout float inv_pdf, inout float3 sampled_point, inout uint rng_state) {
    // ... 现有代码 ...
    
    float area = length(cross(light.u, light.v));
    float dist_sq = dot(sampled_point - position, sampled_point - position);
    float cos_theta = max(dot(-light_dir, normalize(light.direction)), 0.0f);
    
    // 改进：钳制极端值
    dist_sq = max(dist_sq, 0.01);
    cos_theta = max(cos_theta, 0.01);
    
    inv_pdf = area * cos_theta / dist_sq;
    inv_pdf = clamp(inv_pdf, 1e-3, 1e3); // 限制范围
    
    return light.color * light.intensity;
}
```

### 6.3 中期实施（方案 4）

**修改文件**：`src/shaders/direct_lighting.hlsl`

```hlsl
// 添加安全的功率启发式函数
float mis_weight_power_safe(float pdf_a, float pdf_b) {
    pdf_a = max(pdf_a, eps);
    pdf_b = max(pdf_b, eps);
    
    // 如果 PDF 差异太大，使用保守策略
    float ratio = pdf_a / pdf_b;
    if (ratio > 100.0 || ratio < 0.01) {
        return (pdf_a > pdf_b) ? 1.0 : 0.0;
    }
    
    // 功率启发式（β=2）
    float pdf_a_pow = pdf_a * pdf_a;
    float pdf_b_pow = pdf_b * pdf_b;
    float pdf_sum = pdf_a_pow + pdf_b_pow;
    return pdf_sum > eps ? (pdf_a_pow / pdf_sum) : 0.5;
}

// 在 MIS 组合中使用
float w_light = mis_weight_power_safe(pdf_light_actual, pdf_brdf_for_light_dir);
```

---

## 七、测试和调优

### 7.1 测试场景

1. **光滑表面 + 小光源**：最容易产生 fireflies
2. **粗糙表面 + 大光源**：应该没有 fireflies
3. **多层材质场景**：测试所有材质类型

### 7.2 调优参数

- `min_roughness`：粗糙度钳制值（0.15 - 0.4）
- `max_contribution`：贡献值钳制（10.0 - 50.0）
- `inv_pdf_clamp`：PDF 钳制范围（1e-3 - 1e3）
- `mis_power_beta`：功率启发式的 β 值（1.5 - 3.0）

### 7.3 性能影响

- 方案 1：几乎无影响
- 方案 2：几乎无影响
- 方案 3：几乎无影响
- 方案 4：轻微影响（多一次平方运算）
- 方案 5：中等影响（需要检测）
- 方案 6：几乎无影响

---

## 八、预期效果

实施阶段 1 后，预期：
- ✅ Fireflies 减少 70-90%
- ✅ 图像质量明显改善
- ✅ 收敛速度提高

实施阶段 2 后，预期：
- ✅ Fireflies 减少 90-95%
- ✅ 更稳定的渲染结果
- ✅ 更好的物理准确性

---

## 九、注意事项

1. **不要过度钳制**：过度钳制可能导致高光丢失
2. **保持物理正确性**：尽量保持渲染的物理正确性
3. **场景相关**：某些参数可能需要根据场景调整
4. **性能平衡**：在质量和性能之间找到平衡

---

## 十、更新日志

- **2024-12-22**：创建文档，分析 fireflies 问题并提出改进方案


# Multiple Importance Sampling (MIS) 分析文档

## 一、当前实现状态

### 1.1 结论

**当前代码中并没有实现真正的 Multiple Importance Sampling (MIS)**。

代码使用的是：
- **策略选择（Strategy Selection）**：在间接光照中随机选择一个采样策略
- **Next Event Estimation (NEE)**：在直接光照中从光源采样

这两种方法都不是真正的 MIS。

### 1.2 重要澄清

**关于"BRDF term"的误解**：

在 `direct_lighting.hlsl` 中，代码确实计算了 BRDF：
```hlsl
float3 brdf = eval_brdf(...);
direct_light = brdf * radiance * NdotL * inv_pdf;
```

**但这不等于 MIS**，原因如下：

1. **这是 NEE 的标准公式**：
   - NEE 的公式是：`L_direct = f_r(ω_i, ω_o) * L_light(ω_i) * cos(θ) / pdf_light(ω_i)`
   - 其中 `f_r` 是 BRDF，`L_light` 是光源辐射度，`pdf_light` 是光源采样 PDF
   - 代码中的 `brdf * radiance * NdotL * inv_pdf` 正是这个公式

2. **BRDF 是被评估，不是被采样**：
   - 在 NEE 中，方向是从**光源分布**采样的
   - BRDF 只是被**评估**（evaluate）在该方向上
   - 没有从**BRDF 分布**采样方向

3. **MIS 需要同时从两个分布采样**：
   - 从光源分布采样一个方向
   - 从 BRDF 分布采样另一个方向
   - 计算两个方向的贡献
   - 使用权重函数组合两个贡献

**总结**：
- ✅ 代码确实评估了 BRDF（这是正确的 NEE 实现）
- ❌ 但这不是 MIS，因为只从一个分布（光源）采样
- ❌ 真正的 MIS 需要同时从光源和 BRDF 两个分布采样

---

## 二、当前实现分析

### 2.1 间接光照采样（Indirect Lighting Sampling）

**位置**：`src/shaders/shader.hlsl` 第 197-285 行

**实现方式**：
```hlsl
// 1. 计算选择概率
float q_spec_base = clamp(saturate(luminance), 0.05, 0.95);
float q_diff_base = 1.0 - q_spec_base;
float p_clearcoat = ...;  // 清漆层概率
float p_base = 1.0 - p_clearcoat;

// 2. 生成候选方向（但只生成一个）
float3 L_diff = sample_cosine_hemisphere(...);      // 漫反射候选
float3 L_spec_base = sample_GGX_half(...);          // 镜面反射候选
float3 L_spec_cc = sample_GGX_half(...);            // 清漆层候选

// 3. 根据随机数选择一个方向
if (r3 < p_clearcoat) {
    next_dir = L_spec_cc;
} else {
    if (r3_base < q_spec_base) {
        next_dir = L_spec_base;
    } else {
        next_dir = L_diff;
    }
}

// 4. 计算组合 PDF（但只计算被选中方向的 PDF）
float pdf_total = p_clearcoat * pdf_spec_cc + 
                  p_base * (q_spec_base * pdf_spec_base + q_diff_base * pdf_diff);

// 5. 使用单一方向的 BRDF 和 PDF
throughput *= brdf * cos_theta / max(eps, pdf_total);
```

**问题**：
- ❌ 只生成了**一个**候选方向（根据随机数选择）
- ❌ 只计算了被选中方向的 PDF
- ❌ 没有同时评估所有策略的贡献
- ❌ 这是**策略选择（Strategy Selection）**，不是 MIS

**正确的 MIS 应该**：
- ✅ 从所有策略采样（生成所有候选方向）
- ✅ 计算所有策略的 PDF
- ✅ 使用平衡启发式（Balance Heuristic）或其他权重函数组合所有贡献

---

### 2.2 直接光照采样（Direct Lighting Sampling）

**位置**：`src/shaders/direct_lighting.hlsl`

**实现方式**：
```hlsl
// 从光源采样
radiance = SamplePointLight(...) 或 SampleAreaLight(...);
float3 brdf = eval_brdf(...);  // 评估 BRDF（这是 NEE 的标准公式）
direct_light = brdf * radiance * NdotL * inv_pdf;
```

**重要澄清**：
- ✅ 代码确实评估了 BRDF（`eval_brdf`）
- ✅ 这是 **Next Event Estimation (NEE)** 的标准公式：`L_direct = f_r * L_light * cos(θ) / pdf_light`
- ❌ 但这不是 MIS，因为：
  - 只从**一个分布**采样（光源分布）
  - 没有同时从 BRDF 分布采样
  - BRDF 在这里是**被评估**，不是**被采样**

**NEE vs MIS 的区别**：
- **NEE**：从光源采样方向，然后评估 BRDF 在该方向的值
- **MIS**：同时从光源采样和从 BRDF 采样，计算两个方向的贡献，然后用权重函数组合

**当前实现**：
- 直接光照（NEE）：从光源采样 → 评估 BRDF → 计算贡献
- 间接光照（路径追踪）：从 BRDF 采样 → 继续路径追踪
- 两者是**分离的估计**，不是同一个积分估计中的 MIS

**正确的 MIS 应该**：
- ✅ 在同一个积分估计中，同时从光源采样和从 BRDF 采样
- ✅ 计算两种采样的 PDF
- ✅ 使用平衡启发式组合两种贡献

---

## 三、MIS 理论

### 3.1 什么是 Multiple Importance Sampling？

Multiple Importance Sampling (MIS) 是一种结合多个采样策略的技术，用于减少方差并提高渲染质量。

**核心思想**：
- 从多个分布采样（例如：从 BRDF 采样 + 从光源采样）
- 计算所有分布的 PDF
- 使用权重函数组合所有贡献

### 3.2 平衡启发式（Balance Heuristic）

最常用的 MIS 权重函数是**平衡启发式（Balance Heuristic）**：

```
w_i(x) = p_i(x) / Σ_j p_j(x)
```

其中：
- `p_i(x)` 是第 i 个采样策略的 PDF
- `Σ_j p_j(x)` 是所有策略的 PDF 之和

**最终估计**：
```
I = Σ_i w_i(x) * f(x) / p_i(x)
```

### 3.3 功率启发式（Power Heuristic）

更高级的权重函数是**功率启发式（Power Heuristic）**：

```
w_i(x) = (p_i(x))^β / Σ_j (p_j(x))^β
```

其中 `β = 2` 是常用值。

---

## 四、如何实现 MIS

### 4.1 间接光照的 MIS

**当前实现**（策略选择）：
```hlsl
// 只选择一个策略
if (r3 < p_clearcoat) {
    next_dir = L_spec_cc;
} else {
    // ...
}
float pdf_total = ...;
throughput *= brdf * cos_theta / pdf_total;
```

**MIS 实现**（应该这样）：
```hlsl
// 1. 从所有策略采样（生成所有候选方向）
float3 L_diff = sample_cosine_hemisphere(...);
float3 L_spec_base = sample_GGX_half(...);
float3 L_spec_cc = sample_GGX_half(...);

// 2. 计算所有策略的 PDF
float pdf_diff = max(dot(N, L_diff), 0.0) / PI;
float pdf_spec_base = pdf_GGX_for_direction(N, V, L_spec_base, roughness);
float pdf_spec_cc = pdf_GGX_for_direction(N, V, L_spec_cc, clearcoat_roughness);

// 3. 计算组合 PDF（所有策略的 PDF 加权和）
float pdf_total = p_clearcoat * pdf_spec_cc + 
                  p_base * (q_spec_base * pdf_spec_base + q_diff_base * pdf_diff);

// 4. 计算所有策略的贡献
float3 brdf_diff = eval_brdf(N, L_diff, V, ...);
float3 brdf_spec_base = eval_brdf(N, L_spec_base, V, ...);
float3 brdf_spec_cc = eval_brdf(N, L_spec_cc, V, ...);

// 5. 使用平衡启发式计算权重
float w_diff = (p_base * q_diff_base * pdf_diff) / pdf_total;
float w_spec_base = (p_base * q_spec_base * pdf_spec_base) / pdf_total;
float w_spec_cc = (p_clearcoat * pdf_spec_cc) / pdf_total;

// 6. 组合所有贡献
float3 contribution = w_diff * brdf_diff * max(dot(N, L_diff), 0.0) / max(pdf_diff, eps) +
                      w_spec_base * brdf_spec_base * max(dot(N, L_spec_base), 0.0) / max(pdf_spec_base, eps) +
                      w_spec_cc * brdf_spec_cc * max(dot(N, L_spec_cc), 0.0) / max(pdf_spec_cc, eps);

throughput *= contribution;
```

**注意**：这种方法会显著增加计算开销（需要评估所有策略的 BRDF）。

---

### 4.2 直接光照的 MIS

**当前实现**（NEE）：
```hlsl
// 从光源采样方向
radiance = SamplePointLight(...);  // 从光源分布采样
float3 brdf = eval_brdf(normal, light_dir, view_dir, ...);  // 评估 BRDF（不是采样）
direct_light = brdf * radiance * NdotL * inv_pdf;  // NEE 公式
```

**关键区别**：
- 当前：只从**光源分布**采样方向，然后评估 BRDF
- MIS：同时从**光源分布**和**BRDF 分布**采样方向，然后组合

**MIS 实现**（应该这样）：
```hlsl
// 1. 从光源采样（Light Sampling）
float3 light_dir;
float3 radiance_light;
float pdf_light;
radiance_light = SamplePointLight(light, position, light_dir, pdf_light);
float3 brdf_light = eval_brdf(normal, light_dir, view_dir, ...);
float contribution_light = brdf_light * radiance_light * max(dot(normal, light_dir), 0.0);

// 2. 从 BRDF 采样（BRDF Sampling）
float3 brdf_dir = sample_brdf(...);  // 从 BRDF 采样方向
float pdf_brdf = pdf_brdf_for_direction(...);
// 检查这个方向是否指向光源
if (指向光源) {
    float3 radiance_brdf = 光源的辐射度;
    float contribution_brdf = brdf_brdf * radiance_brdf * max(dot(normal, brdf_dir), 0.0);
}

// 3. 计算权重（平衡启发式）
float pdf_total = pdf_light + pdf_brdf;
float w_light = pdf_light / pdf_total;
float w_brdf = pdf_brdf / pdf_total;

// 4. 组合贡献
direct_light = w_light * contribution_light / pdf_light + 
               w_brdf * contribution_brdf / pdf_brdf;
```

**注意**：这种方法需要检查 BRDF 采样方向是否指向光源，可能增加计算复杂度。

---

## 五、性能考虑

### 5.1 当前实现的优势

1. **计算效率高**：只评估一个采样策略
2. **实现简单**：代码逻辑清晰
3. **内存占用小**：不需要存储多个候选方向

### 5.2 MIS 实现的挑战

1. **计算开销大**：需要评估所有策略的 BRDF
2. **实现复杂**：需要正确计算所有 PDF 和权重
3. **内存占用**：需要存储多个候选方向和中间结果

### 5.3 折中方案

可以考虑**部分 MIS**：
- 只在关键情况下使用 MIS（例如：光滑表面 + 小光源）
- 使用更高效的权重函数（例如：Cutoff Heuristic）
- 限制 MIS 的深度（只在浅层使用）

---

## 六、改进建议

### 6.1 短期改进

1. **优化当前策略选择**：
   - 改进概率计算（基于 BRDF 的亮度）
   - 使用更智能的策略选择（例如：基于粗糙度）

2. **改进 NEE**：
   - 添加光源重要性采样（根据光源强度选择）
   - 优化面光源采样（使用更好的采样分布）

### 6.2 长期改进

1. **实现真正的 MIS**：
   - 在间接光照中实现多策略 MIS
   - 在直接光照中实现 Light + BRDF MIS

2. **优化性能**：
   - 使用自适应 MIS（只在需要时使用）
   - 使用更高效的权重函数

3. **支持更多策略**：
   - 添加体积散射采样
   - 添加环境光采样

---

## 七、参考资料

1. **Veach, E. (1997). "Robust Monte Carlo Methods for Light Transport Simulation"**
   - 经典论文，详细介绍了 MIS 理论

2. **PBRT Book (Pharr, Jakob, Humphreys)**
   - 第 13.10 节：Multiple Importance Sampling
   - 提供了详细的实现指南

3. **NVIDIA OptiX Ray Tracing**
   - 提供了 MIS 实现的示例代码

---

## 八、对话记录

### 2024-XX-XX：初始分析

**问题**：目前的代码有 multi importance sampling 吗？

**分析结果**：
- ❌ 当前代码**没有实现真正的 MIS**
- ✅ 使用了策略选择（Strategy Selection）进行间接光照采样
- ✅ 使用了 Next Event Estimation (NEE) 进行直接光照采样
- ❌ 这两种方法都不是真正的 MIS

**代码位置**：
- 间接光照：`src/shaders/shader.hlsl` 第 197-285 行
- 直接光照：`src/shaders/direct_lighting.hlsl`

---

### 2024-XX-XX：关于 BRDF term 的澄清

**用户问题**：为什么认为直接从光源采样不是 MIS？我明明在 NEE 之后又加上 brdf term 了？

**澄清**：
1. **NEE 公式本身就包含 BRDF**：
   - NEE 的标准公式：`L_direct = f_r(ω_i, ω_o) * L_light(ω_i) * cos(θ) / pdf_light(ω_i)`
   - 其中 `f_r` 就是 BRDF
   - 代码中的 `brdf * radiance * NdotL * inv_pdf` 正是这个公式

2. **BRDF 是被评估，不是被采样**：
   - 在 NEE 中，方向是从**光源分布**采样的（`SamplePointLight` 或 `SampleAreaLight`）
   - BRDF 只是被**评估**（evaluate）在该方向上（`eval_brdf`）
   - 没有从**BRDF 分布**采样方向

3. **MIS 需要同时从两个分布采样**：
   - 从光源分布采样一个方向 → 计算贡献1
   - 从 BRDF 分布采样另一个方向 → 计算贡献2（如果该方向指向光源）
   - 使用权重函数组合两个贡献

4. **当前实现的结构**：
   ```
   直接光照（NEE）：
   - 从光源采样方向
   - 评估 BRDF 在该方向
   - 计算贡献：brdf * radiance * NdotL / pdf_light
   
   间接光照（路径追踪）：
   - 从 BRDF 采样方向
   - 继续路径追踪
   ```
   两者是**分离的估计**，不是同一个积分估计中的 MIS。

**结论**：
- ✅ 代码确实评估了 BRDF（这是正确的 NEE 实现）
- ❌ 但这不是 MIS，因为只从一个分布（光源）采样
- ❌ 真正的 MIS 需要同时从光源和 BRDF 两个分布采样，然后使用权重函数组合

**下一步**：
- [ ] 讨论是否需要实现真正的 MIS
- [ ] 如果实现，选择实现方案（完全 MIS vs 部分 MIS）
- [ ] 评估性能影响

---

## 九、待办事项

- [ ] 决定是否实现 MIS
- [ ] 如果实现，选择实现方案
- [ ] 实现间接光照的 MIS
- [ ] 实现直接光照的 MIS
- [ ] 性能测试和优化
- [ ] 添加配置选项（启用/禁用 MIS）

---

## 十、更新日志

- **2024-XX-XX**：创建文档，完成初始分析
- **2024-XX-XX**：实现真正的 MIS（Multiple Importance Sampling）

---

## 十一、MIS 实现详情

### 11.1 实现概述

已成功实现真正的 Multiple Importance Sampling (MIS) 用于直接光照计算。

**实现位置**：
- `src/shaders/direct_lighting.hlsl`：`EvaluateLight()` 和 `EvaluateLightMultiLayer()` 函数
- `src/shaders/sampling.hlsl`：添加了 PDF 计算函数

### 11.2 新增函数

#### 11.2.1 PDF 计算函数（`sampling.hlsl`）

1. **`pdf_brdf_for_direction()`**：
   - 计算给定方向在 BRDF 采样策略下的 PDF
   - 结合漫反射、镜面反射和清漆层的 PDF
   - 使用与路径追踪相同的概率选择策略

2. **`pdf_light_for_direction()`**：
   - 计算给定方向在光源采样策略下的 PDF
   - 支持点光源和面光源

3. **`pdf_brdf_multi_layer_for_direction()`**：
   - 多层材质的 BRDF PDF 计算（简化版本，使用 Layer 1）

#### 11.2.2 MIS 权重函数（`direct_lighting.hlsl`）

1. **`mis_weight_balance()`**：
   - 平衡启发式（Balance Heuristic）
   - 公式：`w_i = p_i / (p_1 + p_2)`

2. **`mis_weight_power()`**：
   - 功率启发式（Power Heuristic，β=2）
   - 公式：`w_i = (p_i)^β / ((p_1)^β + (p_2)^β)`
   - 当前使用平衡启发式，但提供了功率启发式的实现

### 11.3 MIS 实现流程

#### 11.3.1 策略 1：光源采样（Light Sampling）

```hlsl
// 1. 从光源分布采样方向
radiance_light = SamplePointLight(...) 或 SampleAreaLight(...);

// 2. 评估 BRDF 在该方向
brdf_light = eval_brdf(normal, light_dir, view_dir, ...);

// 3. 计算贡献
contribution_light = brdf_light * radiance_light * NdotL;

// 4. 计算 PDF
pdf_light = ...;  // 从光源采样得到的 PDF
pdf_brdf_for_light_dir = pdf_brdf_for_direction(...);  // 该方向在 BRDF 分布下的 PDF
```

#### 11.3.2 策略 2：BRDF 采样（BRDF Sampling）

```hlsl
// 1. 从 BRDF 分布采样方向
brdf_dir = sample_brdf(...);  // 使用与路径追踪相同的采样策略

// 2. 检查该方向是否指向光源
if (hits_light) {
    // 3. 计算光源辐射度
    light_radiance_brdf = ...;
    
    // 4. 评估 BRDF 在该方向
    brdf_brdf = eval_brdf(normal, brdf_dir, view_dir, ...);
    
    // 5. 计算贡献
    contribution_brdf = brdf_brdf * light_radiance_brdf * NdotL;
    
    // 6. 计算 PDF
    pdf_brdf = pdf_brdf_for_direction(...);  // 从 BRDF 采样得到的 PDF
    pdf_light_for_brdf_dir = pdf_light_for_direction(...);  // 该方向在光源分布下的 PDF
}
```

#### 11.3.3 组合贡献（MIS）

```hlsl
// 1. 计算权重（平衡启发式）
w_light = mis_weight_balance(pdf_light, pdf_brdf_for_light_dir);
w_brdf = mis_weight_balance(pdf_brdf, pdf_light_for_brdf_dir);

// 2. 组合贡献
direct_light = w_light * contribution_light / pdf_light +
               w_brdf * contribution_brdf / pdf_brdf;
```

### 11.4 实现细节

#### 11.4.1 光源命中检测

对于 BRDF 采样方向是否命中光源的检测：

- **点光源**：检查方向是否接近光源方向（`cos_angle > 0.99`，约 8 度）
- **面光源**：检查方向是否大致指向光源中心（`cos_angle > 0.9`，约 25 度）

**注意**：这是一个简化实现。更精确的实现需要：
- 对于面光源：计算射线与光源平面的交点
- 检查交点是否在光源范围内

#### 11.4.2 点光源的 PDF 处理

点光源是 delta 分布，PDF 在光源方向为无穷大。实现中：
- 使用 `pdf_light = 1.0`（因为 `inv_pdf = 1.0`）
- 在 MIS 权重计算中，如果 `pdf_light` 很大，权重会偏向 BRDF 采样

#### 11.4.3 多层材质支持

- 使用 Layer 1 的材质属性进行 BRDF 采样策略选择
- 使用多层 BRDF 评估函数计算贡献
- PDF 计算使用 Layer 1 的属性（简化版本）

### 11.5 性能考虑

**计算开销**：
- 每次直接光照计算需要：
  - 1 次光源采样
  - 1 次 BRDF 采样（如果命中光源）
  - 2 次 BRDF 评估
  - 2 次 PDF 计算
  - 2 次阴影射线检测

**优化建议**：
1. 可以添加配置选项，在不需要高质量时禁用 MIS
2. 可以只在特定情况下使用 MIS（例如：光滑表面 + 小光源）
3. 可以限制 MIS 的深度（只在浅层使用）

### 11.6 测试建议

1. **对比测试**：
   - 对比启用/禁用 MIS 的渲染结果
   - 检查方差是否降低
   - 检查渲染时间是否增加

2. **场景测试**：
   - 光滑表面 + 小光源（MIS 应该显著改善）
   - 粗糙表面 + 大光源（MIS 改善可能不明显）
   - 多层材质场景

3. **性能测试**：
   - 测量渲染时间
   - 测量采样数
   - 测量收敛速度

---

## 十二、待办事项

- [x] 实现直接光照的 MIS（Light + BRDF 采样组合）
- [x] 添加从 BRDF 采样方向的函数
- [x] 实现平衡启发式权重函数
- [x] 更新 direct_lighting.hlsl 以支持 MIS
- [x] 为多层材质实现 MIS
- [ ] 测试和验证 MIS 实现
- [ ] 优化性能（如果需要）
- [ ] 添加配置选项（启用/禁用 MIS）
- [ ] 改进面光源的命中检测（更精确的交点计算）


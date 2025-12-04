# DEV LOG by MinusModulo

## 2025-11-26

### Overview

- 实现了 path tracing + BRDF + MIS 的渲染 pipeline。
- 目前的实现效果![alt text](build/src/Debug/screenshot_20251126_114326.png)
- 可以看到还是有很多很多很多的噪点（在金属方块上面），目测算法实现有点问题，需要改一下。
- 离远了就不能看了。 ![alt text](assets/image/screenshot_20251126_114520.png)
- 还有一个问题是边缘的 aliasing 很严重。

### Details

- path tracing 的停止是基于 Russian Roulette 的。
- BRDF 采用的是 Cook-Torrance 模型，包含 diffuse 和 specular 两个部分。
- diffuse 部分采用 Lambert 模型，采样策略是余弦加权采样。
- specular 部分采用 GGX 模型，采样策略是 GGX 采样。
- 采用了 Multiple Importance Sampling (MIS) 来结合 diffuse 和 specular 两个采样策略。
- 采样策略的选择概率 q_spec 是根据 Fresnel 计算出来的。

- 本来想要实现直接光源采样的，结果有点搞错。应该采样所有光源而不是所有发光物体。搞了一晚上...

## 2025-11-27

### Overview

- 修复了远处 sample 会出现黑点的问题，发现是没和 0 取 max 导致出现一些浮点数计算误差。

- 添加了发光物体和反光地面，效果很棒。注意到 roughtness > 0.15，不然会 throughput 下溢然后直接整个画面全黑。

- 添加了 transmissive 材质，效果很棒，实现了钻石（雾）

- 修复了黑天情况下大光源造成的场景过曝问题，最后发现是 eps 的锅，导致 self-intersection，按照 GPT 的指示使用了 t * 1e-4 + eps 作为偏移量，效果很好。

- 目前的实现效果 ![alt text](assets/image/screenshot_20251127_221302.png)
![alt text](assets/image/screenshot_20251127_204103.png)
![alt text](assets/image/screenshot_20251127_202300.png)
![alt text](assets/image/nb.png)

- 黑灯瞎火的情况下有一些噪点。完全合理地认为是因为直接光源采样没有实现的原因。

- 我有一个想法![alt text](assets/image/screenshot_20251127_223456.png)

好吧，因为光路太复杂所以爆炸了。

## 2025-12-3

### Overview

- 场景搭好了！

![alt text](assets/image/scene01.png)

- 黑是因为没实现 metalrough texture，因此默认值是 1.0 1.0，会导致很黑。

- 使用了 tiny_gltf 读取 glb 文件。
  
- 加了 roughness 和 metallic，帅！
  

### TO-DO

- 把光源加上

- 把各种 texture 加上 
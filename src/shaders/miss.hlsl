// ============================================================================
// Miss.hlsl - Miss Shader 模块
// ============================================================================

#include "common.hlsl"

[shader("miss")] void MissMain(inout RayPayload payload) {
  payload.hit = false;
}


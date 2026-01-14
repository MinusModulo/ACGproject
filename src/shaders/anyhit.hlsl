// ============================================================================
// AnyHit.hlsl - Alpha Testing for Shadow Rays
// ============================================================================

#include "common.hlsl"
#include "rng.hlsl"

[shader("anyhit")]
void AnyHitMain(inout RayPayload payload, in BuiltInTriangleIntersectionAttributes attr) {
    // Determine material index using InstanceID()
    uint material_idx = InstanceID();
    
    // Load material
    Material mat = materials[material_idx];

    // If alpha_mode is OPAQUE (0), we accept the hit (default behavior)
    if (mat.alpha_mode == 0) return;

    // Get vertex indices
    uint primitiveID = PrimitiveIndex();
    int index0 = Indices[material_idx][primitiveID * 3 + 0];
    int index1 = Indices[material_idx][primitiveID * 3 + 1];
    int index2 = Indices[material_idx][primitiveID * 3 + 2];

    // Get texcoords
    float2 uv0 = Texcoords[material_idx][index0];
    float2 uv1 = Texcoords[material_idx][index1];
    float2 uv2 = Texcoords[material_idx][index2];

    // Interpolate UV
    float2 bc = attr.barycentrics;
    float3 bary = float3(1.0 - bc.x - bc.y, bc.x, bc.y);
    float2 uv = uv0 * bary.x + uv1 * bary.y + uv2 * bary.z;

    // Handle missing UV coordinates: Generate UV from vertex positions if UV is invalid
    float uv_valid = (length(uv0) > 0.001 || length(uv1) > 0.001 || length(uv2) > 0.001) ? 1.0 : 0.0;
  
    if (uv_valid < 0.5) {
        // Prepare vertex positions
        Vertex v0 = Vertices[material_idx][index0];
        Vertex v1 = Vertices[material_idx][index1];
        Vertex v2 = Vertices[material_idx][index2];
        
        float3 pos0 = v0.position;
        float3 pos1 = v1.position;
        float3 pos2 = v2.position;
        float3 interp_pos = pos0 * bary.x + pos1 * bary.y + pos2 * bary.z;
        
        // Simple box mapping
        float3 abs_pos = abs(interp_pos);
        float max_axis = max(abs_pos.x, max(abs_pos.y, abs_pos.z));
        
        if (abs_pos.x == max_axis) {
            uv = float2(interp_pos.z, interp_pos.y) * 0.5 + 0.5;
        } else if (abs_pos.y == max_axis) {
            uv = float2(interp_pos.x, interp_pos.z) * 0.5 + 0.5;
        } else {
            uv = float2(interp_pos.x, interp_pos.y) * 0.5 + 0.5;
        }
    }

    // Sample Alpha
    float alpha_tex = (mat.base_color_tex >= 0) ? Textures[mat.base_color_tex].SampleLevel(LinearWrap, uv, 0.0f).a : 1.0f;
    float alpha = mat.base_color_factor.a * alpha_tex;

    // Alpha Test
    if (mat.alpha_mode == 1) { // MASK
        if (alpha < 0.5f) {
            IgnoreHit();
        }
    } else if (mat.alpha_mode == 2) { // BLEND
        // Stochastic transparency
        uint rng_state = payload.rng_state;
        
        // RNG state is passed from CastShadowRay
        
        if (rand(rng_state) > alpha) {
            IgnoreHit();
        }
        
        // Update payload state
        payload.rng_state = rng_state;
    }
}

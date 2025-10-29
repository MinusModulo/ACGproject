# Architecture Overview

## System Design

This ray tracing framework is built using a modular, object-oriented approach that separates concerns into distinct components:

```
┌─────────────────────────────────────────────────────────┐
│                     Application                         │
│  - Window Management                                    │
│  - Camera Controls                                      │
│  - Main Loop                                            │
└───────────────┬─────────────────────────────────────────┘
                │
                │ owns
                ↓
┌─────────────────────────────────────────────────────────┐
│                        Scene                            │
│  - Entity Management                                    │
│  - TLAS Builder                                         │
│  - Materials Buffer                                     │
└───────────────┬─────────────────────────────────────────┘
                │
                │ manages multiple
                ↓
┌─────────────────────────────────────────────────────────┐
│                       Entity                            │
│  - Mesh (vertices, indices)                            │
│  - Material                                            │
│  - Transform                                           │
│  - BLAS                                                │
└─────────────────────────────────────────────────────────┘
```

## Data Flow

### Initialization Flow

```
1. Application::OnInit()
   ↓
2. Create Scene
   ↓
3. Create Entities (load meshes, assign materials)
   ↓
4. Add Entities to Scene
   ↓
5. Scene builds BLAS for each Entity
   ↓
6. Scene builds TLAS from all BLAS instances
   ↓
7. Scene creates Materials Buffer
   ↓
8. Load and compile shaders
   ↓
9. Create Ray Tracing Program with resource bindings
```

### Render Loop Flow

```
1. Application::OnUpdate()
   - Process input (camera movement)
   - Update camera buffer
   - (Optional) Update entity transforms
   - (Optional) Call scene_->UpdateInstances()
   ↓
2. Application::OnRender()
   - Create command context
   - Bind ray tracing program
   - Bind resources:
     * Space 0: TLAS
     * Space 1: Output Image
     * Space 2: Camera Buffer
     * Space 3: Materials Buffer
   - Dispatch rays
   - Present to window
```

## Component Details

### Material (Material.h)

**Purpose**: Store material properties for rendering

**Structure**:
```cpp
struct Material {
    glm::vec3 base_color;  // RGB color [0-1]
    float roughness;       // Surface roughness [0-1]
    float metallic;        // Metallic property [0-1]
    float padding[3];      // GPU alignment
};
```

**Key Points**:
- 16-byte aligned for GPU buffer requirements
- Compact representation for efficiency
- Easily extendable for more properties

### Entity (Entity.h, Entity.cpp)

**Purpose**: Represent a single renderable object

**Key Members**:
```cpp
class Entity {
    Mesh<float> mesh_;                          // Geometry data
    Material material_;                          // Material properties
    glm::mat4 transform_;                       // World transform
    unique_ptr<Buffer> vertex_buffer_;          // GPU vertex data
    unique_ptr<Buffer> index_buffer_;           // GPU index data
    unique_ptr<AccelerationStructure> blas_;    // Ray tracing AS
};
```

**Responsibilities**:
1. Load mesh from OBJ file
2. Store material and transform
3. Create GPU buffers for geometry
4. Build BLAS for ray tracing

**Lifecycle**:
```
Constructor → LoadMesh() → BuildBLAS() → (Entity ready for rendering)
```

### Scene (Scene.h, Scene.cpp)

**Purpose**: Manage all entities and build acceleration structures

**Key Members**:
```cpp
class Scene {
    Core* core_;                                    // Graphics core
    vector<shared_ptr<Entity>> entities_;          // All entities
    unique_ptr<AccelerationStructure> tlas_;       // Top-level AS
    unique_ptr<Buffer> materials_buffer_;          // GPU materials
};
```

**Responsibilities**:
1. Store and manage entities
2. Build TLAS from entity BLAS instances
3. Maintain materials buffer synchronized with entities
4. Provide update mechanism for animations

**Key Methods**:
- `AddEntity()`: Add entity and build its BLAS
- `BuildAccelerationStructures()`: Build TLAS and materials buffer (expensive)
- `UpdateInstances()`: Update TLAS with new transforms (cheap)

### Application (app.h, app.cpp)

**Purpose**: Main application controller

**Key Responsibilities**:
1. Window and graphics core management
2. Camera control system
3. Scene initialization
4. Render loop orchestration

**Camera System**:
- WASD movement
- Mouse look (FPS-style)
- Configurable speed and sensitivity

## GPU Resources and Bindings

### Resource Layout

| Space | Type              | Resource           | API Constant                          | Usage                          |
|-------|-------------------|-------------------|---------------------------------------|--------------------------------|
| 0     | Texture (t0)      | TLAS              | RESOURCE_TYPE_ACCELERATION_STRUCTURE | Ray tracing queries           |
| 1     | UAV (u0)          | Output Image      | RESOURCE_TYPE_WRITABLE_IMAGE         | Write ray traced results      |
| 2     | CBV (b0)          | Camera Info       | RESOURCE_TYPE_UNIFORM_BUFFER         | View/projection matrices      |
| 3     | SRV (t0)          | Materials Buffer  | RESOURCE_TYPE_STORAGE_BUFFER         | Per-instance material data    |

### Shader Pipeline

**RayGenMain** (Ray Generation Shader):
1. Calculate ray from camera for each pixel
2. Initialize payload
3. Trace ray through scene
4. Write result to output image

**MissMain** (Miss Shader):
1. Called when ray misses all geometry
2. Returns sky/background color

**ClosestHitMain** (Closest Hit Shader):
1. Called when ray hits geometry
2. Retrieve material using InstanceID()
3. Perform shading calculations
4. Return final color

## Acceleration Structure Hierarchy

```
TLAS (Top-Level Acceleration Structure)
│
├─ Instance 0 → BLAS 0 (Ground)
│   └─ Material Index: 0
│
├─ Instance 1 → BLAS 1 (Red Sphere)
│   └─ Material Index: 1
│
├─ Instance 2 → BLAS 2 (Green Sphere)
│   └─ Material Index: 2
│
└─ Instance 3 → BLAS 3 (Blue Cube)
    └─ Material Index: 3
```

**Key Points**:
- Each Entity has its own BLAS (built once)
- TLAS contains instances of all BLAS (can be updated)
- Instance custom index maps to material buffer index
- This allows per-instance materials efficiently

## Memory Management

### CPU Side
- Smart pointers for automatic cleanup
- `shared_ptr` for entities (can be referenced from multiple places)
- `unique_ptr` for owned resources (buffers, AS, shaders)

### GPU Side
- Buffers managed by graphics core
- Automatic cleanup through destructors
- Order of destruction handled by ownership hierarchy:
  ```
  Application → Scene → Entities → Buffers/BLAS
  ```

## Extension Points

### Adding New Material Properties

1. Modify `Material.h`:
   ```cpp
   struct Material {
       glm::vec3 base_color;
       float roughness;
       float metallic;
       float new_property;  // Add here
       float padding[2];    // Adjust padding
   };
   ```

2. Update shader struct:
   ```hlsl
   struct Material {
       float3 base_color;
       float roughness;
       float metallic;
       float new_property;  // Add here
       float padding[2];    // Match padding
   };
   ```

3. Use in shader code:
   ```hlsl
   Material mat = materials[material_idx];
   float val = mat.new_property;
   ```

### Adding Textures

1. Add texture handle to Entity
2. Update shader bindings (add new space)
3. Modify shader to sample textures
4. Use UV coordinates from mesh

### Adding Lights

1. Create Light struct/class
2. Add lights buffer similar to materials buffer
3. Update shader with light data
4. Implement lighting in ClosestHitMain

### Multi-hit Shaders

1. Create additional hit groups
2. Assign different materials to different hit groups
3. Bind multiple closest hit shaders
4. Use shader binding table offsets

## Performance Considerations

### Build vs Update
- **BuildAccelerationStructures()**: Full rebuild (expensive)
  - Call once during initialization
  - Call when adding/removing entities
  
- **UpdateInstances()**: Partial update (cheap)
  - Call every frame for animations
  - Only updates transforms, not geometry

### Memory
- Each entity stores its own mesh data and BLAS
- Consider instancing for repeated meshes
- Materials buffer grows linearly with entity count

### Optimization Opportunities
1. **Mesh Sharing**: Multiple entities can reference same BLAS
2. **Material Batching**: Group entities by material
3. **LOD System**: Switch meshes based on distance
4. **Culling**: Don't add off-screen entities to TLAS

## Error Handling

### Mesh Loading
- Check `Entity::IsValid()` before adding to scene
- Failed loads are logged but don't crash
- Scene continues with valid entities

### Shader Compilation
- Errors logged to console
- Application may crash if shaders fail
- Check shader code before running

### Buffer Creation
- Managed by LongMarch framework
- Errors typically indicate GPU resource exhaustion
- Consider reducing resolution or entity count

## Thread Safety

**Current State**: Not thread-safe
- All operations on main thread
- Entity/Scene modifications during render loop may cause issues

**Future**: Could be made thread-safe by:
- Command buffering for entity operations
- Double buffering for materials/transforms
- Async BLAS building


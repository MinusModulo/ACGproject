# Ray Tracing Scene System

This is a flexible ray tracing rendering framework built on top of the LongMarch engine. It supports multiple entities, each with their own mesh and material properties.

## Architecture

### Components

1. **Material** (`Material.h`)
   - Defines material properties for rendering
   - Properties: base_color, roughness, metallic
   - Aligned to 16 bytes for GPU compatibility

2. **Entity** (`Entity.h`, `Entity.cpp`)
   - Represents a renderable object in the scene
   - Components:
     - Mesh loaded from OBJ file
     - Material properties
     - Transform matrix (position, rotation, scale)
     - Bottom-Level Acceleration Structure (BLAS)

3. **Scene** (`Scene.h`, `Scene.cpp`)
   - Manages a collection of entities
   - Builds and maintains acceleration structures:
     - Per-entity BLAS (Bottom-Level Acceleration Structure)
     - Scene-wide TLAS (Top-Level Acceleration Structure)
   - Manages materials buffer for GPU access

4. **Application** (`app.h`, `app.cpp`)
   - Main application class
   - Handles:
     - Window management
     - Camera controls (WASD + mouse)
     - Scene initialization
     - Rendering loop

## Usage

### Creating a Scene

```cpp
// Create scene
scene_ = std::make_unique<Scene>(core_.get());

// Add entities
auto ground = std::make_shared<Entity>(
    "meshes/cube.obj",                              // OBJ file path
    Material(glm::vec3(0.8f, 0.8f, 0.8f), 0.8f, 0.0f), // Material
    glm::scale(glm::mat4(1.0f), glm::vec3(10.0f, 0.1f, 10.0f)) // Transform
);
scene_->AddEntity(ground);

// Build acceleration structures
scene_->BuildAccelerationStructures();
```

### Material Properties

```cpp
Material(
    glm::vec3(r, g, b),  // base_color: RGB color (0-1 range)
    roughness,           // roughness: 0.0 (smooth) to 1.0 (rough)
    metallic             // metallic: 0.0 (dielectric) to 1.0 (metal)
)
```

### Loading Meshes

Meshes are loaded from OBJ files using the asset system:
- Files should be placed in `external/LongMarch/assets/meshes/`
- Reference them by relative path: `"meshes/cube.obj"`

Available meshes:
- `cube.obj` - Cube mesh
- `octahedron.obj` - Octahedron (sphere substitute)
- `preview_sphere.obj` - High-quality sphere
- Custom OBJ files you add

### Transform Matrices

Use GLM functions to create transforms:

```cpp
// Translation
glm::translate(glm::mat4(1.0f), glm::vec3(x, y, z))

// Rotation
glm::rotate(glm::mat4(1.0f), angle_radians, glm::vec3(axis_x, axis_y, axis_z))

// Scale
glm::scale(glm::mat4(1.0f), glm::vec3(sx, sy, sz))

// Combined (order matters: Scale -> Rotate -> Translate)
glm::translate(glm::mat4(1.0f), position) * 
glm::rotate(glm::mat4(1.0f), angle, axis) * 
glm::scale(glm::mat4(1.0f), scale)
```

### Updating the Scene

For animated scenes, update entity transforms and rebuild instances:

```cpp
// Update entity transform
entity->SetTransform(new_transform);

// Update TLAS instances (cheap operation)
scene_->UpdateInstances();
```

## Shader System

The ray tracing shader (`shaders/shader.hlsl`) has three main entry points:

1. **RayGenMain** - Generates rays from camera
2. **MissMain** - Handles rays that miss geometry (sky)
3. **ClosestHitMain** - Shades hit geometry using materials

### Material Access in Shaders

Materials are accessed via a structured buffer indexed by instance ID:

```hlsl
uint material_idx = InstanceID();
Material mat = materials[material_idx];
```

## Camera Controls

- **WASD**: Move camera forward/left/backward/right
- **Mouse**: Look around
- **ESC**: Close window

Camera parameters can be adjusted in `app.cpp`:
- `camera_speed_`: Movement speed
- `mouse_sensitivity_`: Mouse look sensitivity
- Initial position and FOV in `OnInit()`

## Rendering Pipeline

1. **Initialization** (`OnInit`)
   - Create window and scene
   - Load entities with meshes and materials
   - Build BLAS for each entity
   - Build TLAS for the scene
   - Compile shaders
   - Create ray tracing program with resource bindings:
     - Space 0: Acceleration Structure (TLAS)
     - Space 1: Writable Image (Output)
     - Space 2: Uniform Buffer (Camera)
     - Space 3: Storage Buffer (Materials)

2. **Update Loop** (`OnUpdate`)
   - Process camera input
   - Update camera buffer
   - Optional: Update entity transforms

3. **Render Loop** (`OnRender`)
   - Bind ray tracing program
   - Bind resources:
     - TLAS (acceleration structure)
     - Output image
     - Camera buffer
     - Materials storage buffer
   - Dispatch rays
   - Present to window

## Adding New Features

### Add a New Entity Type

1. Create the entity with desired properties:
```cpp
auto my_entity = std::make_shared<Entity>(
    "meshes/my_mesh.obj",
    Material(color, roughness, metallic),
    transform
);
scene_->AddEntity(my_entity);
```

### Extend Material Properties

1. Modify `Material.h` to add properties
2. Update shader's `Material` struct to match
3. Modify shader code to use new properties

### Add New Shaders

1. Create shader file in `src/shaders/`
2. Load shader in `OnInit()`
3. Add to ray tracing program

## Example Scene

The default scene includes:
- **Ground plane**: Gray, rough, non-metallic
- **Red sphere**: Bright red, smooth
- **Green sphere**: Green, metallic
- **Blue cube**: Blue, medium roughness

This demonstrates:
- Different geometries (cubes, spheres)
- Various materials (colors, roughness, metallicity)
- Transform operations (translation, scaling)

## Building and Running

The CMakeLists.txt automatically includes all .cpp and .h files in the `src/` directory.

Build with CMake:
```bash
cmake --build out/build/x64-Debug
```

Run:
```bash
./out/build/x64-Debug/src/ShortMarchDemo
```

## Technical Notes

- Each entity has its own BLAS built from its mesh
- The TLAS contains instances of all entity BLASs
- Instance custom index is used to map to materials
- Materials are stored in a GPU buffer for shader access
- Camera uses perspective projection with configurable FOV
- Supports both D3D12 and Vulkan backends


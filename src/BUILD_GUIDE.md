# Build Guide

## Common Build Issues and Solutions

### Issue 1: "unresolved external symbol" for Entity constructor

**Cause**: CMake hasn't picked up the new source files (Entity.cpp, Scene.cpp)

**Solution**:
1. **In Visual Studio**: Right-click on the CMakeLists.txt in Solution Explorer → "Configure Cache"
2. **Command line**: Delete the build directory and reconfigure:
   ```powershell
   Remove-Item -Recurse -Force out/build/x64-Debug
   cmake -S . -B out/build/x64-Debug
   ```
3. The `GLOB_RECURSE` in CMakeLists.txt should automatically pick up all .cpp files

### Issue 2: "cannot open source file 'shaders/shader.hlsl.h'"

**Cause**: The shader packing system hasn't generated the header files yet

**Solution**:
1. Make sure CMake has been configured (see Issue 1)
2. Build the project once - the shader headers are generated during the build process
3. The `PACK_SHADER_CODE` macro automatically:
   - Finds all .hlsl files in src/shaders/
   - Converts them to .h headers in the build directory
   - Creates `built_in_shaders.inl` with helper functions

**What gets generated**:
- `out/build/x64-Debug/src/shaders/shader.hlsl.h` - Shader code as byte array
- `out/build/x64-Debug/src/built_in_shaders.inl` - Included by app.cpp
- Helper function `GetShaderCode("shaders/shader.hlsl")` to access shader code

### Issue 3: 'AccelerationStructureInstance' is not a member of 'grassland::graphics'

**Cause**: Wrong type name used

**Solution**: Use `grassland::graphics::RayTracingInstance` instead

### Issue 4: Type mismatch with MakeInstance transform parameter

**Cause**: `MakeInstance` expects `glm::mat4x3`, but entities use `glm::mat4`

**Solution**: Convert mat4 to mat4x3:
```cpp
glm::mat4x3 transform_3x4 = glm::mat4x3(entity->GetTransform());
```

The last row [0,0,0,1] is dropped since affine transforms only need 3x4 matrices.

## Full Build Process

### Using Visual Studio 2022 with CMake

1. **Open the project**:
   - File → Open → CMake → Select `CMakeLists.txt` in project root

2. **Configure CMake** (if needed):
   - Project → Configure Cache
   - Or: Delete cache and reconfigure from scratch

3. **Build**:
   - Build → Build All
   - Or press F7

4. **Run**:
   - Debug → Start Without Debugging (Ctrl+F5)

### Using Command Line

```powershell
# Configure CMake
cmake -S . -B out/build/x64-Debug -G "Visual Studio 17 2022" -A x64

# Build
cmake --build out/build/x64-Debug --config Debug

# Run
.\out\build\x64-Debug\src\Debug\ShortMarchDemo.exe
```

## Verifying the Build

After a successful build, you should see:
1. No linker errors about Entity or Scene
2. Shader files compiled (messages about PACK_SHADER_CODE)
3. Two windows open when running (D3D12 and Vulkan)
4. A scene with multiple colored objects

## Project Structure

```
src/
├── app.cpp, app.h           - Main application
├── Entity.cpp, Entity.h     - Entity class (mesh + material)
├── Scene.cpp, Scene.h       - Scene manager
├── Material.h               - Material struct
├── main.cpp                 - Entry point
├── CMakeLists.txt           - Build configuration
└── shaders/
    └── shader.hlsl          - Ray tracing shader

out/build/x64-Debug/src/     - Build output
├── built_in_shaders.inl     - Generated shader includes
└── shaders/
    └── shader.hlsl.h        - Generated shader header
```

## Troubleshooting

### IntelliSense errors but builds successfully
- IntelliSense might not find generated headers
- If it builds and runs, ignore IntelliSense errors
- Try: "Rescan Solution" in Visual Studio

### "Cannot find LongMarch" error
- The LongMarch submodule must be initialized
- Run: `git submodule update --init --recursive`

### Missing .obj files at runtime
- Mesh files should be in `external/LongMarch/assets/meshes/`
- Available meshes: cube.obj, octahedron.obj, preview_sphere.obj
- The `FindAssetFile()` function searches for them automatically

### Shader compilation errors
- Check `src/shaders/shader.hlsl` for syntax errors
- Shader model must be `lib_6_3` for ray tracing
- Make sure struct definitions match between HLSL and C++

## Clean Build

If you encounter persistent issues:

```powershell
# Delete build directory
Remove-Item -Recurse -Force out/build

# Reconfigure and build from scratch
cmake -S . -B out/build/x64-Debug
cmake --build out/build/x64-Debug
```

## API Reference Quick Links

### LongMarch Graphics Types
- `grassland::graphics::Core` - Graphics device
- `grassland::graphics::Buffer` - GPU buffer
- `grassland::graphics::AccelerationStructure` - BLAS/TLAS
- `grassland::graphics::RayTracingInstance` - Instance in TLAS
- `grassland::graphics::RayTracingProgram` - Shader program

### Resource Types for Binding
- `RESOURCE_TYPE_ACCELERATION_STRUCTURE` - TLAS
- `RESOURCE_TYPE_WRITABLE_IMAGE` - Output UAV
- `RESOURCE_TYPE_UNIFORM_BUFFER` - Constant buffer
- `RESOURCE_TYPE_STORAGE_BUFFER` - Read-only structured buffer
- `RESOURCE_TYPE_WRITABLE_STORAGE_BUFFER` - Read-write structured buffer

### Ray Tracing Instance Flags
- `RAYTRACING_INSTANCE_FLAG_NONE` - Default
- `RAYTRACING_INSTANCE_FLAG_TRIANGLE_CULL_DISABLE` - Disable culling
- `RAYTRACING_INSTANCE_FLAG_TRIANGLE_FRONT_COUNTERCLOCKWISE` - CCW winding
- `RAYTRACING_INSTANCE_FLAG_FORCE_OPAQUE` - Force opaque
- `RAYTRACING_INSTANCE_FLAG_FORCE_NON_OPAQUE` - Force non-opaque


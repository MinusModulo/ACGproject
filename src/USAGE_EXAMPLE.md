# Usage Examples

## Example 1: Simple Scene with Three Objects

```cpp
void Application::OnInit() {
    // ... window and camera setup ...
    
    scene_ = std::make_unique<Scene>(core_.get());

    // Ground
    auto ground = std::make_shared<Entity>(
        "meshes/cube.obj",
        Material(glm::vec3(0.5f), 0.9f, 0.0f),  // Gray, rough
        glm::scale(glm::translate(glm::mat4(1.0f), glm::vec3(0, -1, 0)), 
                   glm::vec3(20, 0.1f, 20))
    );
    scene_->AddEntity(ground);

    // Red ball
    auto ball = std::make_shared<Entity>(
        "meshes/preview_sphere.obj",
        Material(glm::vec3(1, 0, 0), 0.2f, 0.0f),  // Red, smooth
        glm::translate(glm::mat4(1.0f), glm::vec3(0, 1, 0))
    );
    scene_->AddEntity(ball);

    // Blue metallic cube
    auto cube = std::make_shared<Entity>(
        "meshes/cube.obj",
        Material(glm::vec3(0, 0.3f, 1), 0.3f, 0.9f),  // Blue, metallic
        glm::translate(glm::mat4(1.0f), glm::vec3(3, 1, 0))
    );
    scene_->AddEntity(cube);

    scene_->BuildAccelerationStructures();
    
    // ... rest of initialization ...
}
```

## Example 2: Grid of Objects

```cpp
void Application::OnInit() {
    // ... setup ...
    
    scene_ = std::make_unique<Scene>(core_.get());

    // Create a 5x5 grid of cubes with varying colors
    for (int x = 0; x < 5; x++) {
        for (int z = 0; z < 5; z++) {
            float r = static_cast<float>(x) / 4.0f;
            float b = static_cast<float>(z) / 4.0f;
            
            auto cube = std::make_shared<Entity>(
                "meshes/cube.obj",
                Material(glm::vec3(r, 0.5f, b), 0.5f, 0.0f),
                glm::translate(glm::mat4(1.0f), 
                              glm::vec3(x * 2.5f - 5.0f, 0.5f, z * 2.5f - 5.0f))
            );
            scene_->AddEntity(cube);
        }
    }

    scene_->BuildAccelerationStructures();
    
    // ... rest of initialization ...
}
```

## Example 3: Animated Scene

```cpp
// In app.h, add member variable:
class Application {
    // ...
private:
    std::vector<std::shared_ptr<Entity>> animated_entities_;
    float animation_time_;
};

// In OnInit:
void Application::OnInit() {
    // ... setup ...
    
    scene_ = std::make_unique<Scene>(core_.get());
    animation_time_ = 0.0f;

    // Create entities to animate
    for (int i = 0; i < 5; i++) {
        auto sphere = std::make_shared<Entity>(
            "meshes/preview_sphere.obj",
            Material(glm::vec3(1, 0, 0), 0.3f, 0.0f),
            glm::mat4(1.0f)
        );
        scene_->AddEntity(sphere);
        animated_entities_.push_back(sphere);
    }

    scene_->BuildAccelerationStructures();
    
    // ... rest of initialization ...
}

// In OnUpdate:
void Application::OnUpdate() {
    if (window_->ShouldClose()) {
        window_->CloseWindow();
        alive_ = false;
    }
    if (alive_) {
        ProcessInput();
        
        // Update camera
        CameraObject camera_object{};
        camera_object.screen_to_camera = glm::inverse(
            glm::perspective(glm::radians(60.0f), 
                           (float)window_->GetWidth() / (float)window_->GetHeight(), 
                           0.1f, 10.0f));
        camera_object.camera_to_world =
            glm::inverse(glm::lookAt(camera_pos_, camera_pos_ + camera_front_, camera_up_));
        camera_object_buffer_->UploadData(&camera_object, sizeof(CameraObject));

        // Animate entities
        animation_time_ += 0.01f;
        for (size_t i = 0; i < animated_entities_.size(); i++) {
            float angle = animation_time_ + i * glm::two_pi<float>() / animated_entities_.size();
            float x = 3.0f * cos(angle);
            float z = 3.0f * sin(angle);
            float y = 1.0f + 0.5f * sin(animation_time_ * 2.0f + i);
            
            animated_entities_[i]->SetTransform(
                glm::translate(glm::mat4(1.0f), glm::vec3(x, y, z))
            );
        }
        
        // Update TLAS with new transforms
        scene_->UpdateInstances();
    }
}
```

## Example 4: Different Material Types

```cpp
void Application::OnInit() {
    // ... setup ...
    
    scene_ = std::make_unique<Scene>(core_.get());

    // Rough dielectric (stone)
    auto stone = std::make_shared<Entity>(
        "meshes/preview_sphere.obj",
        Material(glm::vec3(0.4f, 0.4f, 0.4f), 0.9f, 0.0f),
        glm::translate(glm::mat4(1.0f), glm::vec3(-4, 1, 0))
    );
    scene_->AddEntity(stone);

    // Smooth dielectric (plastic)
    auto plastic = std::make_shared<Entity>(
        "meshes/preview_sphere.obj",
        Material(glm::vec3(1.0f, 0.2f, 0.2f), 0.1f, 0.0f),
        glm::translate(glm::mat4(1.0f), glm::vec3(-2, 1, 0))
    );
    scene_->AddEntity(plastic);

    // Rough metal (brushed steel)
    auto brushed_steel = std::make_shared<Entity>(
        "meshes/preview_sphere.obj",
        Material(glm::vec3(0.7f, 0.7f, 0.7f), 0.4f, 1.0f),
        glm::translate(glm::mat4(1.0f), glm::vec3(0, 1, 0))
    );
    scene_->AddEntity(brushed_steel);

    // Smooth metal (chrome)
    auto chrome = std::make_shared<Entity>(
        "meshes/preview_sphere.obj",
        Material(glm::vec3(0.8f, 0.8f, 0.8f), 0.05f, 1.0f),
        glm::translate(glm::mat4(1.0f), glm::vec3(2, 1, 0))
    );
    scene_->AddEntity(chrome);

    // Colored metal (gold)
    auto gold = std::make_shared<Entity>(
        "meshes/preview_sphere.obj",
        Material(glm::vec3(1.0f, 0.85f, 0.3f), 0.15f, 1.0f),
        glm::translate(glm::mat4(1.0f), glm::vec3(4, 1, 0))
    );
    scene_->AddEntity(gold);

    scene_->BuildAccelerationStructures();
    
    // ... rest of initialization ...
}
```

## Example 5: Loading Custom OBJ Files

First, place your OBJ file in `external/LongMarch/assets/meshes/`.

Then use it:

```cpp
void Application::OnInit() {
    // ... setup ...
    
    scene_ = std::make_unique<Scene>(core_.get());

    // Load your custom mesh
    auto my_model = std::make_shared<Entity>(
        "meshes/my_custom_model.obj",  // Your OBJ file
        Material(glm::vec3(0.8f, 0.2f, 0.2f), 0.3f, 0.0f),
        glm::translate(glm::mat4(1.0f), glm::vec3(0, 1, 0))
    );
    
    if (my_model->IsValid()) {
        scene_->AddEntity(my_model);
    } else {
        grassland::LogError("Failed to load custom model!");
    }

    scene_->BuildAccelerationStructures();
    
    // ... rest of initialization ...
}
```

## Example 6: Complex Transform Combinations

```cpp
// Rotated and scaled cube
auto cube = std::make_shared<Entity>(
    "meshes/cube.obj",
    Material(glm::vec3(1, 0, 0), 0.5f, 0.0f),
    glm::translate(glm::mat4(1.0f), glm::vec3(0, 2, 0)) *
    glm::rotate(glm::mat4(1.0f), glm::radians(45.0f), glm::vec3(0, 1, 0)) *
    glm::rotate(glm::mat4(1.0f), glm::radians(30.0f), glm::vec3(1, 0, 0)) *
    glm::scale(glm::mat4(1.0f), glm::vec3(1.5f, 1.5f, 1.5f))
);
scene_->AddEntity(cube);

// Stretched cube (wall)
auto wall = std::make_shared<Entity>(
    "meshes/cube.obj",
    Material(glm::vec3(0.8f), 0.8f, 0.0f),
    glm::translate(glm::mat4(1.0f), glm::vec3(0, 0, -5)) *
    glm::scale(glm::mat4(1.0f), glm::vec3(10, 5, 0.1f))
);
scene_->AddEntity(wall);
```

## Tips

1. **Performance**: Keep the number of entities reasonable (hundreds to low thousands)
2. **Materials**: Use base_color in [0,1] range for realistic results
3. **Roughness**: 0.0-0.3 = glossy, 0.3-0.7 = satin, 0.7-1.0 = matte
4. **Metallic**: Usually 0.0 or 1.0, not in between
5. **Transforms**: Apply in order: Scale → Rotate → Translate
6. **Animation**: Use UpdateInstances() instead of BuildAccelerationStructures() for better performance


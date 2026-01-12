#pragma once
#include "long_march.h"
#include "Scene.h"
#include "Film.h"
#include <memory>

struct CameraObject {
    glm::mat4 screen_to_camera;
    glm::mat4 camera_to_world;
    float aperture;
    float focus_distance;
    glm::vec2 padding;
};

struct VolumeRegion {
    glm::vec3 min_p;
    float pad0;
    glm::vec3 max_p;
    float sigma_t;
    glm::vec3 sigma_s;
    float pad1;
};

struct SkyInfo {
    int use_skybox;
    float env_intensity;
    float bg_intensity;
    float pad_sky;
};

struct RenderSettings {
    int max_bounces;
    float exposure;
    float padding[2];
};

class Application {
public:
    Application(grassland::graphics::BackendAPI api = grassland::graphics::BACKEND_API_DEFAULT);

    ~Application();

    void OnInit();
    void OnClose();
    void OnUpdate();
    void OnRender();
    void ExportFrame(const std::string& filename,
                     const glm::vec3& cam_pos,
                     const glm::vec3& cam_target,
                     const glm::vec3& cam_up,
                     float fov_deg,
                     int width,
                     int height,
                     int max_bounces,
                     int samples);
    void UpdateHoveredEntity(); // Update which entity the mouse is hovering over
    void RenderEntityPanel(); // Render entity inspector panel on the right

    bool IsAlive() const {
        return alive_;
    }

private:
    // Core graphics objects
    std::shared_ptr<grassland::graphics::Core> core_;
    std::unique_ptr<grassland::graphics::Window> window_;

    // Scene management
    std::unique_ptr<Scene> scene_;
    
    // Film for accumulation
    std::unique_ptr<Film> film_;

    // Camera
    std::unique_ptr<grassland::graphics::Buffer> camera_object_buffer_;
    
    // Hover info buffer
    struct HoverInfo {
        int hovered_entity_id;
        int light_count;
    };
    std::unique_ptr<grassland::graphics::Buffer> hover_info_buffer_;
    std::unique_ptr<grassland::graphics::Buffer> volume_info_buffer_;
    std::unique_ptr<grassland::graphics::Buffer> sky_info_buffer_;
    std::unique_ptr<grassland::graphics::Buffer> render_settings_buffer_;

    // Shaders
    std::unique_ptr<grassland::graphics::Shader> raygen_shader_;
    std::unique_ptr<grassland::graphics::Shader> miss_shader_;
    std::unique_ptr<grassland::graphics::Shader> closest_hit_shader_;

    // Rendering
    std::unique_ptr<grassland::graphics::Image> color_image_;
    std::unique_ptr<grassland::graphics::Image> entity_id_image_; // Entity ID buffer for accurate picking
    std::unique_ptr<grassland::graphics::RayTracingProgram> program_;
    bool alive_{ false };

    void RecreateRenderTargets(int width, int height);

    void ProcessInput(); // Helper function for keyboard input


    glm::vec3 camera_pos_;
    glm::vec3 camera_front_;
    glm::vec3 camera_up_;
    float camera_speed_;

    float fov_y_deg_;
    float aperture_;
    float focus_distance_;
    float last_aperture_;
    float last_focus_distance_;
    float last_fov_y_deg_;


    void OnMouseMove(double xpos, double ypos); // Mouse event handler
    void OnMouseButton(int button, int action, int mods, double xpos, double ypos); // Mouse button event handler
    void RenderInfoOverlay(); // Render the info overlay
    void ApplyHoverHighlight(grassland::graphics::Image* image); // Apply hover highlighting as post-process
    void SaveAccumulatedOutput(const std::string& filename); // Save accumulated output to PNG file
    void SaveToneMappedOutput(const std::string& filename); // Save tone-mapped (on-screen) output

    float yaw_;
    float pitch_;
    float last_x_;
    float last_y_;
    float mouse_sensitivity_;
    bool first_mouse_; // Prevents camera jump on first mouse input
    bool camera_enabled_; // Whether camera movement is enabled
    bool last_camera_enabled_; // Track camera state changes to reset accumulation
    bool ui_hidden_; // Whether UI panels are hidden (Tab key toggle)
    
    // Mouse hovering
    double mouse_x_;
    double mouse_y_;
    int hovered_entity_id_; // -1 if no entity hovered
    glm::vec4 hovered_pixel_color_; // Color value at hovered pixel
    
    // Entity selection
    int selected_entity_id_; // -1 if no entity selected

    // Rendering controls
    float exposure_ = 1.0f;
    float env_intensity_ = 1.0f;
    float bg_intensity_ = 1.0f;
};

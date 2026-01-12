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
    int cartoon_enabled;
    float diffuse_bands;
    float specular_hardness;
    float outline_width;
    float outline_threshold;
    // Enhanced color effects
    float hue_shift_strength;
    float rim_power;
    glm::vec3 rim_color;
    float normal_coloring_strength;
    int use_gradient_mapping;
    // Color bleeding effects (插画风格藏色)
    float color_bleeding_strength;
    float color_temperature_shift;
    glm::vec3 shadow_tint;
    glm::vec3 highlight_tint;
    int use_complementary_colors;
    // Anime style rendering (动漫风格)
    float anime_saturation_boost;
    float anime_hue_variation;
    float texture_smoothing;
    float roughness_floor;
    int use_rainbow_mapping;
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
    
    // Cartoon style controls
    bool cartoon_enabled_ = false;
    float diffuse_bands_ = 8.0f;  // Higher default to preserve colors better
    float specular_hardness_ = 0.3f;  // Lower default to preserve highlights
    float outline_width_ = 0.02f;  // Narrower default to reduce over-outlining
    float outline_threshold_ = 0.85f;  // Higher default to only outline true edges
    
    // Enhanced color effects (AGGRESSIVE defaults for vibrant, fancy colors)
    float hue_shift_strength_ = 0.4f;  // Higher default for more color variation
    float rim_power_ = 1.5f;  // Higher default for more visible rim lighting
    glm::vec3 rim_color_ = glm::vec3(0.4f, 0.7f, 1.0f);  // More saturated blue rim
    float normal_coloring_strength_ = 0.5f;  // Higher default for more color variation
    bool use_gradient_mapping_ = true;  // Enabled by default for vibrant colors
    
    // Color bleeding effects (插画风格藏色) - AGGRESSIVE defaults
    float color_bleeding_strength_ = 0.6f;  // Higher default for more fancy look
    float color_temperature_shift_ = 0.7f;  // Higher default for strong temperature separation
    glm::vec3 shadow_tint_ = glm::vec3(0.5f, 0.7f, 1.0f);  // Cool blue for shadows
    glm::vec3 highlight_tint_ = glm::vec3(1.0f, 0.9f, 0.7f);  // Warm yellow for highlights
    bool use_complementary_colors_ = false;  // Optional complementary color bleeding
    
    // Anime style rendering (动漫风格) - AGGRESSIVE defaults for vibrant colors
    float anime_saturation_boost_ = 3.0f;  // Ultra-high saturation boost (300%)
    float anime_hue_variation_ = 0.8f;  // High hue variation for rainbow colors
    float texture_smoothing_ = 0.7f;  // High smoothing to weaken texture details
    float roughness_floor_ = 0.3f;  // Higher roughness floor to reduce specular details
    bool use_rainbow_mapping_ = true;  // Default enabled for rainbow colors
};

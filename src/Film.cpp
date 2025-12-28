#include "Film.h"

Film::Film(grassland::graphics::Core* core, int width, int height)
    : core_(core)
    , width_(width)
    , height_(height)
    , sample_count_(0) {
    
    CreateImages();
    Reset();
}

Film::~Film() {
    accumulated_color_image_.reset();
    accumulated_samples_image_.reset();
    output_image_.reset();
}

void Film::CreateImages() {
    // Create accumulated color image (RGBA32F for high precision accumulation)
    core_->CreateImage(width_, height_, 
                      grassland::graphics::IMAGE_FORMAT_R32G32B32A32_SFLOAT,
                      &accumulated_color_image_);
    
    // Create accumulated samples image (R32_SINT to count samples)
    core_->CreateImage(width_, height_, 
                      grassland::graphics::IMAGE_FORMAT_R32_SINT,
                      &accumulated_samples_image_);
    
    // Create output image (RGBA32F for final result)
    core_->CreateImage(width_, height_, 
                      grassland::graphics::IMAGE_FORMAT_R32G32B32A32_SFLOAT,
                      &output_image_);
}

void Film::Reset() {
    // Clear accumulated color to black
    std::unique_ptr<grassland::graphics::CommandContext> cmd_context;
    core_->CreateCommandContext(&cmd_context);
    cmd_context->CmdClearImage(accumulated_color_image_.get(), { {0.0f, 0.0f, 0.0f, 0.0f} });
    cmd_context->CmdClearImage(accumulated_samples_image_.get(), { {0, 0, 0, 0} });
    cmd_context->CmdClearImage(output_image_.get(), { {0.0f, 0.0f, 0.0f, 0.0f} });
    core_->SubmitCommandContext(cmd_context.get());
    
    sample_count_ = 0;
    grassland::LogInfo("Film accumulation reset");
}

void Film::DevelopToOutput() {
    // This would ideally be done in a compute shader for efficiency
    // For now, we'll do it on the CPU (simple but potentially slow)
    
    if (sample_count_ == 0) {
        return;
    }

    // Download accumulated color and samples
    size_t color_size = width_ * height_ * sizeof(float) * 4;
    std::vector<float> accumulated_colors(width_ * height_ * 4);
    accumulated_color_image_->DownloadData(accumulated_colors.data());

    // Calculate average color and luminance for auto-exposure
    std::vector<glm::vec3> linear_colors(width_ * height_);
    float log_luminance_sum = 0.0f;
    int valid_pixels = 0;

    for (int i = 0; i < width_ * height_; i++) {
        float r = accumulated_colors[i * 4 + 0] / static_cast<float>(sample_count_);
        float g = accumulated_colors[i * 4 + 1] / static_cast<float>(sample_count_);
        float b = accumulated_colors[i * 4 + 2] / static_cast<float>(sample_count_);
        
        linear_colors[i] = glm::vec3(r, g, b);
        
        float lum = 0.2126f * r + 0.7152f * g + 0.0722f * b;
        if (lum > 0.0001f) {
            log_luminance_sum += std::log(lum);
            valid_pixels++;
        }
    }
    
    // Geometric mean of luminance
    float avg_luminance = 0.5f; // Default fallback
    if (valid_pixels > 0) {
        avg_luminance = std::exp(log_luminance_sum / valid_pixels);
    }
    
    // Target luminance (key value)
    float key_value = 0.18f;
    float exposure = key_value / std::max(avg_luminance, 0.0001f);
    exposure = glm::clamp(exposure, 0.1f, 2.0f);

    // Apply tone mapping
    std::vector<float> output_colors(width_ * height_ * 4);
    for (int i = 0; i < width_ * height_; i++) {
        glm::vec3 color = linear_colors[i] * exposure;
        
        // ACES Tone Mapping
        float a = 2.51f;
        float b = 0.03f;
        float c = 2.43f;
        float d = 0.59f;
        float e = 0.14f;
        color = glm::clamp((color * (a * color + b)) / (color * (c * color + d) + e), 0.0f, 1.0f);

        // Gamma to sRGB-ish for display/export consistency
        color.r = pow(color.r, 1.0f / 2.2f);
        color.g = pow(color.g, 1.0f / 2.2f);
        color.b = pow(color.b, 1.0f / 2.2f);
        
        output_colors[i * 4 + 0] = color.r;
        output_colors[i * 4 + 1] = color.g;
        output_colors[i * 4 + 2] = color.b;
        output_colors[i * 4 + 3] = 1.0f;
    }

    // Upload to output image
    output_image_->UploadData(output_colors.data());
}

void Film::Resize(int width, int height) {
    if (width == width_ && height == height_) {
        return;
    }

    width_ = width;
    height_ = height;

    // Recreate images with new dimensions
    accumulated_color_image_.reset();
    accumulated_samples_image_.reset();
    output_image_.reset();

    CreateImages();
    Reset();
    
    grassland::LogInfo("Film resized to {}x{}", width, height);
}


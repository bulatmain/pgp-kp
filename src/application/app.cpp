#include "application/app.h"

#include <chrono>
#include <filesystem>
#include <iostream>

namespace kp::application {

App::App(kp::ports::IRenderer* renderer, kp::ports::IImageWriter* writer)
    : renderer_(renderer), writer_(writer) {}

bool App::Run(const InputConfig& cfg) {
    if (renderer_ == nullptr || writer_ == nullptr) {
        return false;
    }

    const kp::domain::Scene scene = BuildSceneVariant3(cfg);

    for (int frame = 0; frame < cfg.frames; ++frame) {
        kp::domain::Image image(cfg.width, cfg.height);
        const kp::domain::Camera camera = BuildCamera(cfg, frame);

        kp::ports::RenderStats stats;
        const auto t0 = std::chrono::steady_clock::now();
        if (!renderer_->Render(scene, camera, cfg.ssaa_sqrt, &image, &stats)) {
            std::cerr << "render failed for frame " << frame << "\n";
            return false;
        }
        const auto t1 = std::chrono::steady_clock::now();
        const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(t1 - t0).count();

        const std::string path = MakeFramePath(cfg.output_pattern, frame);
        std::filesystem::path file_path(path);
        if (file_path.has_parent_path()) {
            std::error_code ec;
            std::filesystem::create_directories(file_path.parent_path(), ec);
        }

        if (!writer_->Write(path, image)) {
            std::cerr << "write failed for frame " << frame << "\n";
            return false;
        }

        std::cout << frame << '\t' << ms << '\t' << stats.rays << '\n';
    }

    return true;
}

}  // namespace kp::application

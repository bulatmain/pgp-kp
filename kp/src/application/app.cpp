#include "application/app.h"

#include <chrono>
#include <filesystem>
#include <iostream>

namespace kp::application {

App::App(kp::ports::IRenderer* renderer, kp::ports::IImageWriter* writer)
    : renderer(renderer), writer(writer) {}

bool App::run(const InputConfig& cfg) {
    if (this->renderer == nullptr || this->writer == nullptr) {
        return false;
    }

    const kp::domain::Scene scene = buildScene(cfg);

    for (int frame = 0; frame < cfg.frames; ++frame) {
        kp::domain::Image image(cfg.width, cfg.height);
        const kp::domain::Camera camera = buildCamera(cfg, frame);

        kp::ports::RenderStats stats;
        const auto t0 = std::chrono::steady_clock::now();
        if (!this->renderer->render(scene, camera, cfg.ssaaSqrt, &image, &stats)) {
            std::cerr << "render failed for frame " << frame << "\n";
            return false;
        }
        const auto t1 = std::chrono::steady_clock::now();
        const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(t1 - t0).count();

        const std::string path = makeFramePath(cfg.outputPattern, frame);
        std::filesystem::path filePath(path);
        if (filePath.has_parent_path()) {
            std::error_code ec;
            std::filesystem::create_directories(filePath.parent_path(), ec);
        }

        if (!this->writer->write(path, image)) {
            std::cerr << "write failed for frame " << frame << "\n";
            return false;
        }

        std::cout << frame << '\t' << ms << '\t' << stats.rays << '\n';
    }

    return true;
}

}  // namespace kp::application

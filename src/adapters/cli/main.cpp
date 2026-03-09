#include <iostream>
#include <memory>
#include <string>

#include "adapters/cpu/cpu_renderer.h"
#include "adapters/file/ppm_writer.h"
#include "adapters/gpu/cuda_renderer.h"
#include "application/app.h"
#include "application/config.h"

namespace {

enum class Mode {
    Cpu,
    Gpu,
    PrintDefault,
};

Mode ParseMode(int argc, char** argv) {
    if (argc <= 1) {
        return Mode::Gpu;
    }

    const std::string arg = argv[1];
    if (arg == "--cpu") return Mode::Cpu;
    if (arg == "--gpu") return Mode::Gpu;
    if (arg == "--default") return Mode::PrintDefault;

    return Mode::Gpu;
}

}  // namespace

int main(int argc, char** argv) {
    const Mode mode = ParseMode(argc, argv);

    kp::application::InputConfig cfg = kp::application::InputConfig::Default();

    if (mode == Mode::PrintDefault) {
        kp::application::PrintDefaultConfig(std::cout, cfg);
        return 0;
    }

    if (!kp::application::ParseInputConfig(std::cin, &cfg)) {
        std::cerr << "stdin config not found or invalid, defaults are used\n";
    }

    std::unique_ptr<kp::ports::IRenderer> renderer;
    if (mode == Mode::Cpu) {
        renderer = std::make_unique<kp::adapters::cpu::CpuRenderer>();
    } else {
        renderer = std::make_unique<kp::adapters::gpu::CudaRenderer>();
    }

    kp::adapters::file::PpmWriter writer;
    kp::application::App app(renderer.get(), &writer);
    return app.Run(cfg) ? 0 : 1;
}

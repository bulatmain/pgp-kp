#pragma once

#include "application/config.h"
#include "ports/image_writer.h"
#include "ports/renderer.h"

namespace kp::application {

class App {
public:
    App(kp::ports::IRenderer* renderer, kp::ports::IImageWriter* writer);

    bool run(const InputConfig& cfg);

private:
    kp::ports::IRenderer* renderer;
    kp::ports::IImageWriter* writer;
};

}  // namespace kp::application

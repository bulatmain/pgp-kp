#pragma once

#include "application/config.h"
#include "ports/image_writer.h"
#include "ports/renderer.h"

namespace kp::application {

class App {
public:
    App(kp::ports::IRenderer* renderer, kp::ports::IImageWriter* writer);

    bool Run(const InputConfig& cfg);

private:
    kp::ports::IRenderer* renderer_;
    kp::ports::IImageWriter* writer_;
};

}  // namespace kp::application

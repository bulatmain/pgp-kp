#pragma once

#include "ports/renderer.h"

namespace kp::adapters::cpu {

class CpuRenderer final : public kp::ports::IRenderer {
public:
    bool render(const kp::domain::Scene& scene,
                const kp::domain::Camera& camera,
                int ssaaSqrt,
                kp::domain::Image* outImage,
                kp::ports::RenderStats* outStats) override;
};

}  // namespace kp::adapters::cpu

#pragma once

#include "ports/renderer.h"

namespace kp::adapters::cpu {

class CpuRenderer final : public kp::ports::IRenderer {
public:
    bool Render(const kp::domain::Scene& scene,
                const kp::domain::Camera& camera,
                int ssaa_sqrt,
                kp::domain::Image* out_image,
                kp::ports::RenderStats* out_stats) override;
};

}  // namespace kp::adapters::cpu

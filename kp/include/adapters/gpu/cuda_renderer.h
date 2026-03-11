#pragma once

#include "ports/renderer.h"

namespace kp::adapters::gpu {

class CudaRenderer final : public kp::ports::IRenderer {
public:
    bool render(const kp::domain::Scene& scene,
                const kp::domain::Camera& camera,
                int ssaaSqrt,
                kp::domain::Image* outImage,
                kp::ports::RenderStats* outStats) override;
};

}  // namespace kp::adapters::gpu

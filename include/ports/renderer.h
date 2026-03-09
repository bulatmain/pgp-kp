#pragma once

#include <cstdint>

#include "domain/scene.h"

namespace kp::ports {

struct RenderStats {
    std::uint64_t rays = 0;
};

class IRenderer {
public:
    virtual ~IRenderer() = default;
    virtual bool render(const kp::domain::Scene& scene,
                        const kp::domain::Camera& camera,
                        int ssaaSqrt,
                        kp::domain::Image* outImage,
                        RenderStats* outStats) = 0;
};

}  // namespace kp::ports

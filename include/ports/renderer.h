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
    virtual bool Render(const kp::domain::Scene& scene,
                        const kp::domain::Camera& camera,
                        int ssaa_sqrt,
                        kp::domain::Image* out_image,
                        RenderStats* out_stats) = 0;
};

}  // namespace kp::ports

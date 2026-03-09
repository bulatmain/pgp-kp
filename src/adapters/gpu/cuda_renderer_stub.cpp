#include "adapters/gpu/cuda_renderer.h"

#include <iostream>

namespace kp::adapters::gpu {

bool CudaRenderer::Render(const kp::domain::Scene&,
                          const kp::domain::Camera&,
                          int,
                          kp::domain::Image*,
                          kp::ports::RenderStats*) {
    std::cerr << "GPU renderer is unavailable: CUDA toolkit (nvcc) is not installed\n";
    return false;
}

}  // namespace kp::adapters::gpu

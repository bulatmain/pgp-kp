#include "adapters/gpu/cuda_renderer.h"

#include <cuda_runtime.h>

#include <cfloat>
#include <cmath>
#include <iostream>
#include <vector>

namespace kp::adapters::gpu {
namespace {

struct GpuVec3 {
    float x;
    float y;
    float z;
};

struct GpuTriangle {
    GpuVec3 a;
    GpuVec3 b;
    GpuVec3 c;
    GpuVec3 color;
};

struct GpuLight {
    GpuVec3 position;
    GpuVec3 color;
};

struct GpuCamera {
    GpuVec3 position;
    GpuVec3 forward;
    GpuVec3 right;
    GpuVec3 up;
    float half_w;
    float half_h;
};

__host__ __device__ GpuVec3 Make(float x, float y, float z) {
    GpuVec3 v{x, y, z};
    return v;
}

__host__ __device__ GpuVec3 Add(GpuVec3 a, GpuVec3 b) { return Make(a.x + b.x, a.y + b.y, a.z + b.z); }
__host__ __device__ GpuVec3 Sub(GpuVec3 a, GpuVec3 b) { return Make(a.x - b.x, a.y - b.y, a.z - b.z); }
__host__ __device__ GpuVec3 Mul(GpuVec3 v, float s) { return Make(v.x * s, v.y * s, v.z * s); }
__host__ __device__ GpuVec3 Hadamard(GpuVec3 a, GpuVec3 b) { return Make(a.x * b.x, a.y * b.y, a.z * b.z); }

__host__ __device__ float Dot(GpuVec3 a, GpuVec3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
__host__ __device__ GpuVec3 Cross(GpuVec3 a, GpuVec3 b) {
    return Make(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
}

__host__ __device__ float Len(GpuVec3 v) { return sqrtf(Dot(v, v)); }

__host__ __device__ GpuVec3 Normalize(GpuVec3 v) {
    const float l = Len(v);
    if (l <= 1e-8f) {
        return Make(0.0f, 0.0f, 0.0f);
    }
    return Mul(v, 1.0f / l);
}

__host__ __device__ float Clamp(float x, float lo, float hi) {
    if (x < lo) return lo;
    if (x > hi) return hi;
    return x;
}

__device__ bool IntersectTriangle(
    GpuVec3 ro,
    GpuVec3 rd,
    const GpuTriangle& tri,
    float* out_t,
    GpuVec3* out_normal
) {
    const float eps = 1e-6f;
    const GpuVec3 e1 = Sub(tri.b, tri.a);
    const GpuVec3 e2 = Sub(tri.c, tri.a);
    const GpuVec3 p = Cross(rd, e2);
    const float det = Dot(e1, p);
    if (fabsf(det) < eps) {
        return false;
    }

    const float inv_det = 1.0f / det;
    const GpuVec3 tvec = Sub(ro, tri.a);
    const float u = Dot(tvec, p) * inv_det;
    if (u < 0.0f || u > 1.0f) return false;

    const GpuVec3 q = Cross(tvec, e1);
    const float v = Dot(rd, q) * inv_det;
    if (v < 0.0f || u + v > 1.0f) return false;

    const float t = Dot(e2, q) * inv_det;
    if (t <= eps) return false;

    *out_t = t;
    *out_normal = Normalize(Cross(e1, e2));
    return true;
}

__global__ void RenderKernel(
    const GpuTriangle* triangles,
    int triangles_count,
    GpuLight light,
    GpuCamera camera,
    int width,
    int height,
    int ssaa_sqrt,
    GpuVec3* out
) {
    const int x = blockIdx.x * blockDim.x + threadIdx.x;
    const int y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x >= width || y >= height) return;

    const int spp = ssaa_sqrt * ssaa_sqrt;
    GpuVec3 accum = Make(0.0f, 0.0f, 0.0f);

    for (int sy = 0; sy < ssaa_sqrt; ++sy) {
        for (int sx = 0; sx < ssaa_sqrt; ++sx) {
            const float u = (static_cast<float>(x) + (static_cast<float>(sx) + 0.5f) / ssaa_sqrt) / static_cast<float>(width);
            const float v = (static_cast<float>(y) + (static_cast<float>(sy) + 0.5f) / ssaa_sqrt) / static_cast<float>(height);
            const float px = (2.0f * u - 1.0f) * camera.half_w;
            const float py = (1.0f - 2.0f * v) * camera.half_h;

            const GpuVec3 ro = camera.position;
            const GpuVec3 rd = Normalize(Add(camera.forward, Add(Mul(camera.right, px), Mul(camera.up, py))));

            float best_t = FLT_MAX;
            GpuVec3 best_normal = Make(0.0f, 0.0f, 0.0f);
            GpuVec3 best_color = Make(0.0f, 0.0f, 0.0f);
            bool hit = false;

            for (int i = 0; i < triangles_count; ++i) {
                float t = FLT_MAX;
                GpuVec3 normal;
                if (!IntersectTriangle(ro, rd, triangles[i], &t, &normal)) continue;
                if (t < best_t) {
                    best_t = t;
                    best_normal = normal;
                    best_color = triangles[i].color;
                    hit = true;
                }
            }

            GpuVec3 sample = Make(0.04f, 0.06f, 0.1f);
            if (hit) {
                const GpuVec3 hit_point = Add(ro, Mul(rd, best_t));
                const GpuVec3 l = Normalize(Sub(light.position, hit_point));
                const float ndotl = Clamp(Dot(best_normal, l), 0.0f, 1.0f);
                const float intensity = 0.15f + 0.85f * ndotl;
                sample = Hadamard(Mul(best_color, intensity), light.color);
            }

            accum = Add(accum, sample);
        }
    }

    out[y * width + x] = Mul(accum, 1.0f / static_cast<float>(spp));
}

GpuVec3 ToGpu(const kp::domain::Vec3& v) { return Make(v.x, v.y, v.z); }
kp::domain::Vec3 ToHost(const GpuVec3& v) { return kp::domain::Vec3(v.x, v.y, v.z); }

}  // namespace

bool CudaRenderer::Render(const kp::domain::Scene& scene,
                          const kp::domain::Camera& camera,
                          int ssaa_sqrt,
                          kp::domain::Image* out_image,
                          kp::ports::RenderStats* out_stats) {
    if (out_image == nullptr || out_stats == nullptr || scene.triangles.empty() || scene.lights.empty()) {
        return false;
    }

    const int w = out_image->width;
    const int h = out_image->height;
    const int n = static_cast<int>(scene.triangles.size());

    std::vector<GpuTriangle> host_triangles(static_cast<size_t>(n));
    for (int i = 0; i < n; ++i) {
        host_triangles[static_cast<size_t>(i)] = GpuTriangle{
            ToGpu(scene.triangles[static_cast<size_t>(i)].a),
            ToGpu(scene.triangles[static_cast<size_t>(i)].b),
            ToGpu(scene.triangles[static_cast<size_t>(i)].c),
            ToGpu(scene.triangles[static_cast<size_t>(i)].color)};
    }

    const kp::domain::Vec3 forward = kp::domain::Normalize(camera.target - camera.position);
    const kp::domain::Vec3 right = kp::domain::Normalize(kp::domain::Cross(forward, camera.up));
    const kp::domain::Vec3 up = kp::domain::Normalize(kp::domain::Cross(right, forward));
    const float aspect = static_cast<float>(w) / static_cast<float>(h);
    const float fov_rad = camera.fov_deg * 0.01745329251994329577f;
    const float half_h = std::tan(fov_rad * 0.5f);
    const float half_w = half_h * aspect;

    const GpuCamera gpu_cam = {
        ToGpu(camera.position),
        ToGpu(forward),
        ToGpu(right),
        ToGpu(up),
        half_w,
        half_h,
    };

    const GpuLight gpu_light = {ToGpu(scene.lights[0].position), ToGpu(scene.lights[0].color)};

    GpuTriangle* d_triangles = nullptr;
    GpuVec3* d_pixels = nullptr;

    cudaError_t err = cudaMalloc(&d_triangles, sizeof(GpuTriangle) * static_cast<size_t>(n));
    if (err != cudaSuccess) {
        std::cerr << "cudaMalloc triangles failed: " << cudaGetErrorString(err) << "\n";
        return false;
    }

    err = cudaMalloc(&d_pixels, sizeof(GpuVec3) * static_cast<size_t>(w * h));
    if (err != cudaSuccess) {
        std::cerr << "cudaMalloc pixels failed: " << cudaGetErrorString(err) << "\n";
        cudaFree(d_triangles);
        return false;
    }

    err = cudaMemcpy(d_triangles, host_triangles.data(), sizeof(GpuTriangle) * static_cast<size_t>(n), cudaMemcpyHostToDevice);
    if (err != cudaSuccess) {
        std::cerr << "cudaMemcpy triangles failed: " << cudaGetErrorString(err) << "\n";
        cudaFree(d_triangles);
        cudaFree(d_pixels);
        return false;
    }

    const dim3 block(16, 16);
    const dim3 grid((w + block.x - 1) / block.x, (h + block.y - 1) / block.y);

    RenderKernel<<<grid, block>>>(d_triangles, n, gpu_light, gpu_cam, w, h, ssaa_sqrt, d_pixels);
    err = cudaGetLastError();
    if (err != cudaSuccess) {
        std::cerr << "kernel launch failed: " << cudaGetErrorString(err) << "\n";
        cudaFree(d_triangles);
        cudaFree(d_pixels);
        return false;
    }

    err = cudaDeviceSynchronize();
    if (err != cudaSuccess) {
        std::cerr << "cudaDeviceSynchronize failed: " << cudaGetErrorString(err) << "\n";
        cudaFree(d_triangles);
        cudaFree(d_pixels);
        return false;
    }

    std::vector<GpuVec3> host_pixels(static_cast<size_t>(w * h));
    err = cudaMemcpy(host_pixels.data(), d_pixels, sizeof(GpuVec3) * static_cast<size_t>(w * h), cudaMemcpyDeviceToHost);
    if (err != cudaSuccess) {
        std::cerr << "cudaMemcpy pixels failed: " << cudaGetErrorString(err) << "\n";
        cudaFree(d_triangles);
        cudaFree(d_pixels);
        return false;
    }

    for (int i = 0; i < w * h; ++i) {
        out_image->pixels[static_cast<size_t>(i)] = ToHost(host_pixels[static_cast<size_t>(i)]);
    }

    cudaFree(d_triangles);
    cudaFree(d_pixels);

    const int spp = ssaa_sqrt * ssaa_sqrt;
    out_stats->rays = static_cast<std::uint64_t>(w) * static_cast<std::uint64_t>(h) * static_cast<std::uint64_t>(spp);
    return true;
}

}  // namespace kp::adapters::gpu

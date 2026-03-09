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
    float halfW;
    float halfH;
};

__host__ __device__ GpuVec3 makeVec3(float x, float y, float z) {
    GpuVec3 v{x, y, z};
    return v;
}

__host__ __device__ GpuVec3 add(GpuVec3 a, GpuVec3 b) { return makeVec3(a.x + b.x, a.y + b.y, a.z + b.z); }
__host__ __device__ GpuVec3 sub(GpuVec3 a, GpuVec3 b) { return makeVec3(a.x - b.x, a.y - b.y, a.z - b.z); }
__host__ __device__ GpuVec3 mul(GpuVec3 v, float s) { return makeVec3(v.x * s, v.y * s, v.z * s); }
__host__ __device__ GpuVec3 hadamard(GpuVec3 a, GpuVec3 b) { return makeVec3(a.x * b.x, a.y * b.y, a.z * b.z); }

__host__ __device__ float dot(GpuVec3 a, GpuVec3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
__host__ __device__ GpuVec3 cross(GpuVec3 a, GpuVec3 b) {
    return makeVec3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
}

__host__ __device__ float len(GpuVec3 v) { return sqrtf(dot(v, v)); }

__host__ __device__ GpuVec3 normalize(GpuVec3 v) {
    const float l = len(v);
    if (l <= 1e-8f) {
        return makeVec3(0.0f, 0.0f, 0.0f);
    }
    return mul(v, 1.0f / l);
}

__host__ __device__ float clamp(float x, float lo, float hi) {
    if (x < lo) return lo;
    if (x > hi) return hi;
    return x;
}

__device__ bool intersectTriangle(
    GpuVec3 ro,
    GpuVec3 rd,
    const GpuTriangle& tri,
    float* out_t,
    GpuVec3* out_normal
) {
    const float eps = 1e-6f;
    const GpuVec3 e1 = sub(tri.b, tri.a);
    const GpuVec3 e2 = sub(tri.c, tri.a);
    const GpuVec3 p = cross(rd, e2);
    const float det = dot(e1, p);
    if (fabsf(det) < eps) {
        return false;
    }

    const float invDet = 1.0f / det;
    const GpuVec3 tvec = sub(ro, tri.a);
    const float u = dot(tvec, p) * invDet;
    if (u < 0.0f || u > 1.0f) return false;

    const GpuVec3 q = cross(tvec, e1);
    const float v = dot(rd, q) * invDet;
    if (v < 0.0f || u + v > 1.0f) return false;

    const float t = dot(e2, q) * invDet;
    if (t <= eps) return false;

    *out_t = t;
    *out_normal = normalize(cross(e1, e2));
    return true;
}

__global__ void renderKernel(
    const GpuTriangle* triangles,
    int trianglesCount,
    GpuLight light,
    GpuCamera camera,
    int width,
    int height,
    int ssaaSqrt,
    GpuVec3* out
) {
    const int x = blockIdx.x * blockDim.x + threadIdx.x;
    const int y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x >= width || y >= height) return;

    const int spp = ssaaSqrt * ssaaSqrt;
    GpuVec3 accum = makeVec3(0.0f, 0.0f, 0.0f);

    for (int sy = 0; sy < ssaaSqrt; ++sy) {
        for (int sx = 0; sx < ssaaSqrt; ++sx) {
            const float u = (static_cast<float>(x) + (static_cast<float>(sx) + 0.5f) / ssaaSqrt) / static_cast<float>(width);
            const float v = (static_cast<float>(y) + (static_cast<float>(sy) + 0.5f) / ssaaSqrt) / static_cast<float>(height);
            const float px = (2.0f * u - 1.0f) * camera.halfW;
            const float py = (1.0f - 2.0f * v) * camera.halfH;

            const GpuVec3 ro = camera.position;
            const GpuVec3 rd = normalize(add(camera.forward, add(mul(camera.right, px), mul(camera.up, py))));

            float bestT = FLT_MAX;
            GpuVec3 bestNormal = makeVec3(0.0f, 0.0f, 0.0f);
            GpuVec3 bestColor = makeVec3(0.0f, 0.0f, 0.0f);
            bool hit = false;

            for (int i = 0; i < trianglesCount; ++i) {
                float t = FLT_MAX;
                GpuVec3 normal;
                if (!intersectTriangle(ro, rd, triangles[i], &t, &normal)) continue;
                if (t < bestT) {
                    bestT = t;
                    bestNormal = normal;
                    bestColor = triangles[i].color;
                    hit = true;
                }
            }

            GpuVec3 sample = makeVec3(0.04f, 0.06f, 0.1f);
            if (hit) {
                const GpuVec3 hitPoint = add(ro, mul(rd, bestT));
                const GpuVec3 l = normalize(sub(light.position, hitPoint));
                const float ndotl = clamp(dot(bestNormal, l), 0.0f, 1.0f);
                const float intensity = 0.15f + 0.85f * ndotl;
                sample = hadamard(mul(bestColor, intensity), light.color);
            }

            accum = add(accum, sample);
        }
    }

    out[y * width + x] = mul(accum, 1.0f / static_cast<float>(spp));
}

GpuVec3 toGpu(const kp::domain::Vec3& v) { return makeVec3(v.x, v.y, v.z); }
kp::domain::Vec3 toHost(const GpuVec3& v) { return kp::domain::Vec3(v.x, v.y, v.z); }

}  // namespace

bool CudaRenderer::render(const kp::domain::Scene& scene,
                          const kp::domain::Camera& camera,
                          int ssaaSqrt,
                          kp::domain::Image* outImage,
                          kp::ports::RenderStats* outStats) {
    if (outImage == nullptr || outStats == nullptr || scene.triangles.empty() || scene.lights.empty()) {
        return false;
    }

    const int w = outImage->width;
    const int h = outImage->height;
    const int n = static_cast<int>(scene.triangles.size());

    std::vector<GpuTriangle> host_triangles(static_cast<size_t>(n));
    for (int i = 0; i < n; ++i) {
        host_triangles[static_cast<size_t>(i)] = GpuTriangle{
            toGpu(scene.triangles[static_cast<size_t>(i)].a),
            toGpu(scene.triangles[static_cast<size_t>(i)].b),
            toGpu(scene.triangles[static_cast<size_t>(i)].c),
            toGpu(scene.triangles[static_cast<size_t>(i)].color)};
    }

    const kp::domain::Vec3 forward = kp::domain::normalize(camera.target - camera.position);
    const kp::domain::Vec3 right = kp::domain::normalize(kp::domain::cross(forward, camera.up));
    const kp::domain::Vec3 up = kp::domain::normalize(kp::domain::cross(right, forward));
    const float aspect = static_cast<float>(w) / static_cast<float>(h);
    const float fovRad = camera.fovDeg * 0.01745329251994329577f;
    const float halfH = std::tan(fovRad * 0.5f);
    const float halfW = halfH * aspect;

    const GpuCamera gpu_cam = {
        toGpu(camera.position),
        toGpu(forward),
        toGpu(right),
        toGpu(up),
        halfW,
        halfH,
    };

    const GpuLight gpu_light = {toGpu(scene.lights[0].position), toGpu(scene.lights[0].color)};

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

    renderKernel<<<grid, block>>>(d_triangles, n, gpu_light, gpu_cam, w, h, ssaaSqrt, d_pixels);
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
        outImage->pixels[static_cast<size_t>(i)] = toHost(host_pixels[static_cast<size_t>(i)]);
    }

    cudaFree(d_triangles);
    cudaFree(d_pixels);

    const int spp = ssaaSqrt * ssaaSqrt;
    outStats->rays = static_cast<std::uint64_t>(w) * static_cast<std::uint64_t>(h) * static_cast<std::uint64_t>(spp);
    return true;
}

}  // namespace kp::adapters::gpu

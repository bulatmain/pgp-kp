#include "adapters/cpu/cpu_renderer.h"

#include <cfloat>
#include <cmath>

namespace kp::adapters::cpu {
namespace {

struct Hit {
    float t = FLT_MAX;
    kp::domain::Vec3 normal;
    kp::domain::Vec3 color;
    kp::domain::Vec3 point;
    bool ok = false;
};

bool intersectTriangle(const kp::domain::Ray& ray, const kp::domain::Triangle& tri, float* out_t, kp::domain::Vec3* out_normal) {
    const float eps = 1e-6f;

    const kp::domain::Vec3 e1 = tri.b - tri.a;
    const kp::domain::Vec3 e2 = tri.c - tri.a;
    const kp::domain::Vec3 p = kp::domain::cross(ray.dir, e2);
    const float det = kp::domain::dot(e1, p);
    if (std::fabs(det) < eps) {
        return false;
    }

    const float inv_det = 1.0f / det;
    const kp::domain::Vec3 tvec = ray.origin - tri.a;
    const float u = kp::domain::dot(tvec, p) * inv_det;
    if (u < 0.0f || u > 1.0f) {
        return false;
    }

    const kp::domain::Vec3 q = kp::domain::cross(tvec, e1);
    const float v = kp::domain::dot(ray.dir, q) * inv_det;
    if (v < 0.0f || u + v > 1.0f) {
        return false;
    }

    const float t = kp::domain::dot(e2, q) * inv_det;
    if (t <= eps) {
        return false;
    }

    if (out_t != nullptr) {
        *out_t = t;
    }
    if (out_normal != nullptr) {
        *out_normal = kp::domain::normalize(kp::domain::cross(e1, e2));
    }
    return true;
}

Hit tracePrimary(const kp::domain::Scene& scene, const kp::domain::Ray& ray) {
    Hit hit;
    for (const auto& tri : scene.triangles) {
        float t = FLT_MAX;
        kp::domain::Vec3 normal;
        if (!intersectTriangle(ray, tri, &t, &normal)) {
            continue;
        }

        if (t < hit.t) {
            hit.t = t;
            hit.normal = normal;
            hit.color = tri.color;
            hit.point = ray.origin + ray.dir * t;
            hit.ok = true;
        }
    }
    return hit;
}

bool inShadow(const kp::domain::Scene& scene, const kp::domain::Vec3& point, const kp::domain::Vec3& light_pos) {
    const kp::domain::Vec3 to_light = light_pos - point;
    const float max_t = kp::domain::length(to_light);
    if (max_t <= 1e-6f) {
        return false;
    }

    kp::domain::Ray shadow_ray;
    shadow_ray.origin = point;
    shadow_ray.dir = to_light / max_t;

    for (const auto& tri : scene.triangles) {
        float t = FLT_MAX;
        if (intersectTriangle(shadow_ray, tri, &t, nullptr) && t < max_t - 1e-3f) {
            return true;
        }
    }
    return false;
}

kp::domain::Vec3 shade(const kp::domain::Scene& scene, const Hit& hit) {
    const float ambient = 0.15f;
    if (!hit.ok) {
        return kp::domain::Vec3(0.04f, 0.06f, 0.1f);
    }

    const kp::domain::Light light = scene.lights[0];
    const kp::domain::Vec3 origin = hit.point + hit.normal * 1e-3f;
    if (inShadow(scene, origin, light.position)) {
        return hit.color * ambient;
    }

    const kp::domain::Vec3 l = kp::domain::normalize(light.position - hit.point);
    const float ndotl = kp::domain::clamp(kp::domain::dot(hit.normal, l), 0.0f, 1.0f);
    const float intensity = ambient + 0.85f * ndotl;
    return kp::domain::hadamard(hit.color * intensity, light.color);
}

}  // namespace

bool CpuRenderer::render(const kp::domain::Scene& scene,
                         const kp::domain::Camera& camera,
                         int ssaaSqrt,
                         kp::domain::Image* outImage,
                         kp::ports::RenderStats* outStats) {
    if (outImage == nullptr || outStats == nullptr) {
        return false;
    }

    const int w = outImage->width;
    const int h = outImage->height;

    const kp::domain::Vec3 forward = kp::domain::normalize(camera.target - camera.position);
    const kp::domain::Vec3 right = kp::domain::normalize(kp::domain::cross(forward, camera.up));
    const kp::domain::Vec3 up = kp::domain::normalize(kp::domain::cross(right, forward));

    const float aspect = static_cast<float>(w) / static_cast<float>(h);
    const float fov_rad = camera.fovDeg * 0.01745329251994329577f;
    const float half_h = std::tan(fov_rad * 0.5f);
    const float half_w = half_h * aspect;

    const int spp = ssaaSqrt * ssaaSqrt;
    outStats->rays = static_cast<std::uint64_t>(w) * static_cast<std::uint64_t>(h) * static_cast<std::uint64_t>(spp);

    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            kp::domain::Vec3 accum;
            for (int sy = 0; sy < ssaaSqrt; ++sy) {
                for (int sx = 0; sx < ssaaSqrt; ++sx) {
                    const float u = (static_cast<float>(x) + (static_cast<float>(sx) + 0.5f) / ssaaSqrt) / static_cast<float>(w);
                    const float v = (static_cast<float>(y) + (static_cast<float>(sy) + 0.5f) / ssaaSqrt) / static_cast<float>(h);

                    const float px = (2.0f * u - 1.0f) * half_w;
                    const float py = (1.0f - 2.0f * v) * half_h;

                    kp::domain::Ray ray;
                    ray.origin = camera.position;
                    ray.dir = kp::domain::normalize(forward + right * px + up * py);

                    const Hit hit = tracePrimary(scene, ray);
                    accum += shade(scene, hit);
                }
            }
            outImage->at(x, y) = accum / static_cast<float>(spp);
        }
    }

    return true;
}

}  // namespace kp::adapters::cpu

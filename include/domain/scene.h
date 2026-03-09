#pragma once

#include <string>
#include <vector>

#include "domain/math.h"

namespace kp::domain {

struct Ray {
    Vec3 origin;
    Vec3 dir;
};

struct Triangle {
    Vec3 a;
    Vec3 b;
    Vec3 c;
    Vec3 color;
};

struct Light {
    Vec3 position;
    Vec3 color;
};

struct Camera {
    Vec3 position;
    Vec3 target;
    Vec3 up;
    float fov_deg;
};

struct Image {
    int width = 0;
    int height = 0;
    std::vector<Vec3> pixels;

    Image() = default;
    Image(int w, int h) : width(w), height(h), pixels(static_cast<size_t>(w * h), Vec3()) {}

    Vec3& At(int x, int y) { return pixels[static_cast<size_t>(y * width + x)]; }
    const Vec3& At(int x, int y) const { return pixels[static_cast<size_t>(y * width + x)]; }
};

struct Scene {
    std::vector<Triangle> triangles;
    std::vector<Light> lights;
};

}  // namespace kp::domain

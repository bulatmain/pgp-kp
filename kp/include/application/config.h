#pragma once

#include <istream>
#include <ostream>
#include <string>
#include <vector>

#include "domain/scene.h"

namespace kp::application {

struct OrbitParams {
    float baseR = 7.0f;
    float baseZ = 3.0f;
    float basePhi = 0.0f;

    float ampR = 0.0f;
    float ampZ = 0.0f;

    float omegaR = 0.0f;
    float omegaZ = 0.0f;
    float omegaPhi = 1.0f;

    float phaseR = 0.0f;
    float phaseZ = 0.0f;
};

struct BodyConfig {
    kp::domain::Vec3 center;
    kp::domain::Vec3 color;
    float radius = 1.0f;
    float reflection = 0.0f;
    float transparency = 0.0f;
    int lightsOnEdge = 0;
};

struct FloorConfig {
    kp::domain::Vec3 p0;
    kp::domain::Vec3 p1;
    kp::domain::Vec3 p2;
    kp::domain::Vec3 p3;
    std::string texturePath;
    kp::domain::Vec3 tint;
    float reflection = 0.0f;
};

struct InputConfig {
    int frames = 120;
    std::string outputPattern = "out/frame_%d.ppm";
    int width = 800;
    int height = 600;
    float fovDeg = 70.0f;

    OrbitParams cameraOrbit;
    OrbitParams targetOrbit;

    BodyConfig bodies[3];
    FloorConfig floor;

    std::vector<kp::domain::Light> lights;

    int maxDepth = 1;
    int ssaaSqrt = 1;

    static InputConfig makeDefault();
};

bool parseInputConfig(std::istream& in, InputConfig* out);
void printDefaultConfig(std::ostream& out, const InputConfig& cfg);

kp::domain::Scene buildScene(const InputConfig& cfg);
kp::domain::Camera buildCamera(const InputConfig& cfg, int frameIndex);
std::string makeFramePath(const std::string& pattern, int frameIndex);

}  // namespace kp::application

#pragma once

#include <istream>
#include <ostream>
#include <string>
#include <vector>

#include "domain/scene.h"

namespace kp::application {

struct OrbitParams {
    float base_r = 7.0f;
    float base_z = 3.0f;
    float base_phi = 0.0f;

    float amp_r = 0.0f;
    float amp_z = 0.0f;

    float omega_r = 0.0f;
    float omega_z = 0.0f;
    float omega_phi = 1.0f;

    float phase_r = 0.0f;
    float phase_z = 0.0f;
};

struct BodyConfig {
    kp::domain::Vec3 center;
    kp::domain::Vec3 color;
    float radius = 1.0f;
    float reflection = 0.0f;
    float transparency = 0.0f;
    int lights_on_edge = 0;
};

struct FloorConfig {
    kp::domain::Vec3 p0;
    kp::domain::Vec3 p1;
    kp::domain::Vec3 p2;
    kp::domain::Vec3 p3;
    std::string texture_path;
    kp::domain::Vec3 tint;
    float reflection = 0.0f;
};

struct InputConfig {
    int frames = 120;
    std::string output_pattern = "out/frame_%d.ppm";
    int width = 800;
    int height = 600;
    float fov_deg = 70.0f;

    OrbitParams camera_orbit;
    OrbitParams target_orbit;

    BodyConfig bodies[3];
    FloorConfig floor;

    std::vector<kp::domain::Light> lights;

    int max_depth = 1;
    int ssaa_sqrt = 1;

    static InputConfig Default();
};

bool ParseInputConfig(std::istream& in, InputConfig* out);
void PrintDefaultConfig(std::ostream& out, const InputConfig& cfg);

kp::domain::Scene BuildSceneVariant3(const InputConfig& cfg);
kp::domain::Camera BuildCamera(const InputConfig& cfg, int frame_idx);
std::string MakeFramePath(const std::string& pattern, int frame_idx);

}  // namespace kp::application

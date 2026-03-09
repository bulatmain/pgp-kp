#include "application/config.h"

#include <cmath>
#include <cstdio>
#include <iomanip>
#include <sstream>

#include "domain/polyhedra.h"

namespace kp::application {
namespace {

kp::domain::Vec3 CylToCartesian(float r, float phi, float z) {
    return kp::domain::Vec3(r * std::cos(phi), r * std::sin(phi), z);
}

kp::domain::Vec3 EvalOrbit(const OrbitParams& o, float t) {
    const float r = o.base_r + o.amp_r * std::sin(o.omega_r * t + o.phase_r);
    const float z = o.base_z + o.amp_z * std::sin(o.omega_z * t + o.phase_z);
    const float phi = o.base_phi + o.omega_phi * t;
    return CylToCartesian(r, phi, z);
}

}  // namespace

InputConfig InputConfig::Default() {
    InputConfig cfg;
    cfg.frames = 180;
    cfg.output_pattern = "out/frame_%04d.ppm";
    cfg.width = 960;
    cfg.height = 540;
    cfg.fov_deg = 75.0f;

    cfg.camera_orbit.base_r = 8.0f;
    cfg.camera_orbit.base_z = 3.2f;
    cfg.camera_orbit.omega_phi = 1.0f;

    cfg.target_orbit.base_r = 0.0f;
    cfg.target_orbit.base_z = 0.8f;
    cfg.target_orbit.omega_phi = 0.5f;

    cfg.bodies[0].center = kp::domain::Vec3(-2.0f, -0.6f, 0.8f);
    cfg.bodies[0].color = kp::domain::Vec3(1.0f, 0.2f, 0.2f);
    cfg.bodies[0].radius = 1.0f;

    cfg.bodies[1].center = kp::domain::Vec3(0.2f, 1.1f, 1.0f);
    cfg.bodies[1].color = kp::domain::Vec3(0.1f, 0.9f, 0.2f);
    cfg.bodies[1].radius = 1.2f;

    cfg.bodies[2].center = kp::domain::Vec3(2.0f, -0.8f, 1.1f);
    cfg.bodies[2].color = kp::domain::Vec3(0.2f, 0.5f, 1.0f);
    cfg.bodies[2].radius = 1.3f;

    cfg.floor.p0 = kp::domain::Vec3(-6.0f, -6.0f, -1.0f);
    cfg.floor.p1 = kp::domain::Vec3(-6.0f, 6.0f, -1.0f);
    cfg.floor.p2 = kp::domain::Vec3(6.0f, 6.0f, -1.0f);
    cfg.floor.p3 = kp::domain::Vec3(6.0f, -6.0f, -1.0f);
    cfg.floor.texture_path = "-";
    cfg.floor.tint = kp::domain::Vec3(0.8f, 0.8f, 0.85f);

    cfg.lights = {kp::domain::Light{kp::domain::Vec3(-2.0f, -1.0f, 7.0f), kp::domain::Vec3(1.0f, 1.0f, 1.0f)}};

    cfg.max_depth = 1;
    cfg.ssaa_sqrt = 1;
    return cfg;
}

bool ParseInputConfig(std::istream& in, InputConfig* out) {
    if (out == nullptr) {
        return false;
    }

    InputConfig cfg;
    if (!(in >> cfg.frames)) {
        return false;
    }

    if (!(in >> cfg.output_pattern)) {
        return false;
    }

    if (!(in >> cfg.width >> cfg.height >> cfg.fov_deg)) {
        return false;
    }

    OrbitParams* orbits[2] = {&cfg.camera_orbit, &cfg.target_orbit};
    for (OrbitParams* orbit : orbits) {
        if (!(in >> orbit->base_r >> orbit->base_z >> orbit->base_phi)) return false;
        if (!(in >> orbit->amp_r >> orbit->amp_z)) return false;
        if (!(in >> orbit->omega_r >> orbit->omega_z >> orbit->omega_phi)) return false;
        if (!(in >> orbit->phase_r >> orbit->phase_z)) return false;
    }

    for (int i = 0; i < 3; ++i) {
        BodyConfig& b = cfg.bodies[i];
        if (!(in >> b.center.x >> b.center.y >> b.center.z)) return false;
        if (!(in >> b.color.x >> b.color.y >> b.color.z)) return false;
        if (!(in >> b.radius >> b.reflection >> b.transparency >> b.lights_on_edge)) return false;
    }

    FloorConfig& f = cfg.floor;
    if (!(in >> f.p0.x >> f.p0.y >> f.p0.z)) return false;
    if (!(in >> f.p1.x >> f.p1.y >> f.p1.z)) return false;
    if (!(in >> f.p2.x >> f.p2.y >> f.p2.z)) return false;
    if (!(in >> f.p3.x >> f.p3.y >> f.p3.z)) return false;
    if (!(in >> f.texture_path)) return false;
    if (!(in >> f.tint.x >> f.tint.y >> f.tint.z >> f.reflection)) return false;

    int lights_count = 0;
    if (!(in >> lights_count)) return false;
    if (lights_count < 1) lights_count = 1;
    if (lights_count > 4) lights_count = 4;

    cfg.lights.clear();
    cfg.lights.reserve(static_cast<size_t>(lights_count));
    for (int i = 0; i < lights_count; ++i) {
        kp::domain::Light light;
        if (!(in >> light.position.x >> light.position.y >> light.position.z)) return false;
        if (!(in >> light.color.x >> light.color.y >> light.color.z)) return false;
        cfg.lights.push_back(light);
    }

    if (!(in >> cfg.max_depth >> cfg.ssaa_sqrt)) {
        return false;
    }

    if (cfg.frames < 1) cfg.frames = 1;
    if (cfg.width < 1) cfg.width = 1;
    if (cfg.height < 1) cfg.height = 1;
    if (cfg.ssaa_sqrt < 1) cfg.ssaa_sqrt = 1;

    *out = cfg;
    return true;
}

void PrintDefaultConfig(std::ostream& out, const InputConfig& cfg) {
    out << cfg.frames << '\n';
    out << cfg.output_pattern << '\n';
    out << cfg.width << ' ' << cfg.height << ' ' << cfg.fov_deg << '\n';

    const OrbitParams orbits[2] = {cfg.camera_orbit, cfg.target_orbit};
    for (const OrbitParams& o : orbits) {
        out << o.base_r << ' ' << o.base_z << ' ' << o.base_phi << '\n';
        out << o.amp_r << ' ' << o.amp_z << '\n';
        out << o.omega_r << ' ' << o.omega_z << ' ' << o.omega_phi << '\n';
        out << o.phase_r << ' ' << o.phase_z << '\n';
    }

    for (int i = 0; i < 3; ++i) {
        const BodyConfig& b = cfg.bodies[i];
        out << b.center.x << ' ' << b.center.y << ' ' << b.center.z << '\n';
        out << b.color.x << ' ' << b.color.y << ' ' << b.color.z << '\n';
        out << b.radius << '\n';
        out << b.reflection << '\n';
        out << b.transparency << '\n';
        out << b.lights_on_edge << '\n';
    }

    const FloorConfig& f = cfg.floor;
    out << f.p0.x << ' ' << f.p0.y << ' ' << f.p0.z << '\n';
    out << f.p1.x << ' ' << f.p1.y << ' ' << f.p1.z << '\n';
    out << f.p2.x << ' ' << f.p2.y << ' ' << f.p2.z << '\n';
    out << f.p3.x << ' ' << f.p3.y << ' ' << f.p3.z << '\n';
    out << f.texture_path << '\n';
    out << f.tint.x << ' ' << f.tint.y << ' ' << f.tint.z << '\n';
    out << f.reflection << '\n';

    out << cfg.lights.size() << '\n';
    for (const auto& light : cfg.lights) {
        out << light.position.x << ' ' << light.position.y << ' ' << light.position.z << '\n';
        out << light.color.x << ' ' << light.color.y << ' ' << light.color.z << '\n';
    }

    out << cfg.max_depth << ' ' << cfg.ssaa_sqrt << '\n';
}

kp::domain::Scene BuildSceneVariant3(const InputConfig& cfg) {
    kp::domain::Scene scene;

    const kp::domain::PolyhedronType types[3] = {
        kp::domain::PolyhedronType::Tetrahedron,
        kp::domain::PolyhedronType::Hexahedron,
        kp::domain::PolyhedronType::Icosahedron,
    };

    for (int i = 0; i < 3; ++i) {
        const BodyConfig& b = cfg.bodies[i];
        std::vector<kp::domain::Triangle> mesh = kp::domain::BuildPolyhedronMesh(types[i], b.center, b.radius, b.color);
        scene.triangles.insert(scene.triangles.end(), mesh.begin(), mesh.end());
    }

    const kp::domain::Vec3 floor_color = cfg.floor.tint;
    scene.triangles.push_back(kp::domain::Triangle{cfg.floor.p0, cfg.floor.p1, cfg.floor.p2, floor_color});
    scene.triangles.push_back(kp::domain::Triangle{cfg.floor.p0, cfg.floor.p2, cfg.floor.p3, floor_color});

    if (cfg.lights.empty()) {
        scene.lights.push_back(kp::domain::Light{kp::domain::Vec3(-2.0f, -1.0f, 7.0f), kp::domain::Vec3(1.0f, 1.0f, 1.0f)});
    } else {
        scene.lights.push_back(cfg.lights[0]);
    }

    return scene;
}

kp::domain::Camera BuildCamera(const InputConfig& cfg, int frame_idx) {
    const float t = (cfg.frames <= 1)
        ? 0.0f
        : (2.0f * static_cast<float>(M_PI) * static_cast<float>(frame_idx) / static_cast<float>(cfg.frames - 1));

    kp::domain::Camera cam;
    cam.position = EvalOrbit(cfg.camera_orbit, t);
    cam.target = EvalOrbit(cfg.target_orbit, t);
    cam.up = kp::domain::Vec3(0.0f, 0.0f, 1.0f);
    cam.fov_deg = cfg.fov_deg;
    return cam;
}

std::string MakeFramePath(const std::string& pattern, int frame_idx) {
    if (pattern.find('%') == std::string::npos) {
        return pattern + std::to_string(frame_idx);
    }

    char buf[4096];
    const int n = std::snprintf(buf, sizeof(buf), pattern.c_str(), frame_idx);
    if (n <= 0) {
        return pattern + std::to_string(frame_idx);
    }
    return std::string(buf);
}

}  // namespace kp::application

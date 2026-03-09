#include "application/config.h"

#include <cmath>
#include <cstdio>
#include <iomanip>
#include <sstream>

#include "domain/polyhedra.h"

namespace kp::application {
namespace {

kp::domain::Vec3 cylToCartesian(float r, float phi, float z) {
    return kp::domain::Vec3(r * std::cos(phi), r * std::sin(phi), z);
}

kp::domain::Vec3 evalOrbit(const OrbitParams& o, float t) {
    const float r = o.baseR + o.ampR * std::sin(o.omegaR * t + o.phaseR);
    const float z = o.baseZ + o.ampZ * std::sin(o.omegaZ * t + o.phaseZ);
    const float phi = o.basePhi + o.omegaPhi * t;
    return cylToCartesian(r, phi, z);
}

}  // namespace

InputConfig InputConfig::makeDefault() {
    InputConfig cfg;
    cfg.frames = 180;
    cfg.outputPattern = "out/frame_%04d.ppm";
    cfg.width = 960;
    cfg.height = 540;
    cfg.fovDeg = 75.0f;

    cfg.cameraOrbit.baseR = 8.0f;
    cfg.cameraOrbit.baseZ = 3.2f;
    cfg.cameraOrbit.omegaPhi = 1.0f;

    cfg.targetOrbit.baseR = 0.0f;
    cfg.targetOrbit.baseZ = 0.8f;
    cfg.targetOrbit.omegaPhi = 0.5f;

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
    cfg.floor.texturePath = "-";
    cfg.floor.tint = kp::domain::Vec3(0.8f, 0.8f, 0.85f);

    cfg.lights = {kp::domain::Light{kp::domain::Vec3(-2.0f, -1.0f, 7.0f), kp::domain::Vec3(1.0f, 1.0f, 1.0f)}};

    cfg.maxDepth = 1;
    cfg.ssaaSqrt = 1;
    return cfg;
}

bool parseInputConfig(std::istream& in, InputConfig* out) {
    if (out == nullptr) {
        return false;
    }

    InputConfig cfg;
    if (!(in >> cfg.frames)) {
        return false;
    }

    if (!(in >> cfg.outputPattern)) {
        return false;
    }

    if (!(in >> cfg.width >> cfg.height >> cfg.fovDeg)) {
        return false;
    }

    OrbitParams* orbits[2] = {&cfg.cameraOrbit, &cfg.targetOrbit};
    for (OrbitParams* orbit : orbits) {
        if (!(in >> orbit->baseR >> orbit->baseZ >> orbit->basePhi)) return false;
        if (!(in >> orbit->ampR >> orbit->ampZ)) return false;
        if (!(in >> orbit->omegaR >> orbit->omegaZ >> orbit->omegaPhi)) return false;
        if (!(in >> orbit->phaseR >> orbit->phaseZ)) return false;
    }

    for (int i = 0; i < 3; ++i) {
        BodyConfig& b = cfg.bodies[i];
        if (!(in >> b.center.x >> b.center.y >> b.center.z)) return false;
        if (!(in >> b.color.x >> b.color.y >> b.color.z)) return false;
        if (!(in >> b.radius >> b.reflection >> b.transparency >> b.lightsOnEdge)) return false;
    }

    FloorConfig& f = cfg.floor;
    if (!(in >> f.p0.x >> f.p0.y >> f.p0.z)) return false;
    if (!(in >> f.p1.x >> f.p1.y >> f.p1.z)) return false;
    if (!(in >> f.p2.x >> f.p2.y >> f.p2.z)) return false;
    if (!(in >> f.p3.x >> f.p3.y >> f.p3.z)) return false;
    if (!(in >> f.texturePath)) return false;
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

    if (!(in >> cfg.maxDepth >> cfg.ssaaSqrt)) {
        return false;
    }

    if (cfg.frames < 1) cfg.frames = 1;
    if (cfg.width < 1) cfg.width = 1;
    if (cfg.height < 1) cfg.height = 1;
    if (cfg.ssaaSqrt < 1) cfg.ssaaSqrt = 1;

    *out = cfg;
    return true;
}

void printDefaultConfig(std::ostream& out, const InputConfig& cfg) {
    out << cfg.frames << '\n';
    out << cfg.outputPattern << '\n';
    out << cfg.width << ' ' << cfg.height << ' ' << cfg.fovDeg << '\n';

    const OrbitParams orbits[2] = {cfg.cameraOrbit, cfg.targetOrbit};
    for (const OrbitParams& o : orbits) {
        out << o.baseR << ' ' << o.baseZ << ' ' << o.basePhi << '\n';
        out << o.ampR << ' ' << o.ampZ << '\n';
        out << o.omegaR << ' ' << o.omegaZ << ' ' << o.omegaPhi << '\n';
        out << o.phaseR << ' ' << o.phaseZ << '\n';
    }

    for (int i = 0; i < 3; ++i) {
        const BodyConfig& b = cfg.bodies[i];
        out << b.center.x << ' ' << b.center.y << ' ' << b.center.z << '\n';
        out << b.color.x << ' ' << b.color.y << ' ' << b.color.z << '\n';
        out << b.radius << '\n';
        out << b.reflection << '\n';
        out << b.transparency << '\n';
        out << b.lightsOnEdge << '\n';
    }

    const FloorConfig& f = cfg.floor;
    out << f.p0.x << ' ' << f.p0.y << ' ' << f.p0.z << '\n';
    out << f.p1.x << ' ' << f.p1.y << ' ' << f.p1.z << '\n';
    out << f.p2.x << ' ' << f.p2.y << ' ' << f.p2.z << '\n';
    out << f.p3.x << ' ' << f.p3.y << ' ' << f.p3.z << '\n';
    out << f.texturePath << '\n';
    out << f.tint.x << ' ' << f.tint.y << ' ' << f.tint.z << '\n';
    out << f.reflection << '\n';

    out << cfg.lights.size() << '\n';
    for (const auto& light : cfg.lights) {
        out << light.position.x << ' ' << light.position.y << ' ' << light.position.z << '\n';
        out << light.color.x << ' ' << light.color.y << ' ' << light.color.z << '\n';
    }

    out << cfg.maxDepth << ' ' << cfg.ssaaSqrt << '\n';
}

kp::domain::Scene buildScene(const InputConfig& cfg) {
    kp::domain::Scene scene;

    const kp::domain::PolyhedronType types[3] = {
        kp::domain::PolyhedronType::Tetrahedron,
        kp::domain::PolyhedronType::Hexahedron,
        kp::domain::PolyhedronType::Icosahedron,
    };

    for (int i = 0; i < 3; ++i) {
        const BodyConfig& b = cfg.bodies[i];
        std::vector<kp::domain::Triangle> mesh = kp::domain::buildPolyhedronMesh(types[i], b.center, b.radius, b.color);
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

kp::domain::Camera buildCamera(const InputConfig& cfg, int frameIndex) {
    const float t = (cfg.frames <= 1)
        ? 0.0f
        : (2.0f * static_cast<float>(M_PI) * static_cast<float>(frameIndex) / static_cast<float>(cfg.frames - 1));

    kp::domain::Camera cam;
    cam.position = evalOrbit(cfg.cameraOrbit, t);
    cam.target = evalOrbit(cfg.targetOrbit, t);
    cam.up = kp::domain::Vec3(0.0f, 0.0f, 1.0f);
    cam.fovDeg = cfg.fovDeg;
    return cam;
}

std::string makeFramePath(const std::string& pattern, int frameIndex) {
    if (pattern.find('%') == std::string::npos) {
        return pattern + std::to_string(frameIndex);
    }

    char buf[4096];
    const int n = std::snprintf(buf, sizeof(buf), pattern.c_str(), frameIndex);
    if (n <= 0) {
        return pattern + std::to_string(frameIndex);
    }
    return std::string(buf);
}

}  // namespace kp::application

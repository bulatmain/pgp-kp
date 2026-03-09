#pragma once

#include <vector>

#include "domain/scene.h"

namespace kp::domain {

enum class PolyhedronType {
    Tetrahedron,
    Hexahedron,
    Icosahedron
};

std::vector<Triangle> BuildPolyhedronMesh(PolyhedronType type, const Vec3& center, float radius, const Vec3& color);

}  // namespace kp::domain

#include "domain/polyhedra.h"

#include <array>
#include <cmath>

namespace kp::domain {
namespace {

std::vector<Triangle> BuildFromIndexedFaces(
    const std::vector<Vec3>& vertices,
    const std::vector<std::array<int, 3>>& faces,
    const Vec3& center,
    float radius,
    const Vec3& color
) {
    float max_len = 0.0f;
    for (const Vec3& v : vertices) {
        const float l = Length(v);
        if (l > max_len) {
            max_len = l;
        }
    }

    const float scale = (max_len > 1e-8f) ? (radius / max_len) : 1.0f;
    std::vector<Vec3> scaled;
    scaled.reserve(vertices.size());
    for (const Vec3& v : vertices) {
        scaled.push_back(center + v * scale);
    }

    std::vector<Triangle> triangles;
    triangles.reserve(faces.size());
    for (const auto& face : faces) {
        triangles.push_back(Triangle{scaled[face[0]], scaled[face[1]], scaled[face[2]], color});
    }
    return triangles;
}

std::vector<Triangle> BuildTetrahedron(const Vec3& center, float radius, const Vec3& color) {
    const std::vector<Vec3> vertices = {
        Vec3(1.0f, 1.0f, 1.0f),
        Vec3(-1.0f, -1.0f, 1.0f),
        Vec3(-1.0f, 1.0f, -1.0f),
        Vec3(1.0f, -1.0f, -1.0f),
    };

    const std::vector<std::array<int, 3>> faces = {
        {0, 1, 2},
        {0, 3, 1},
        {0, 2, 3},
        {1, 3, 2},
    };

    return BuildFromIndexedFaces(vertices, faces, center, radius, color);
}

std::vector<Triangle> BuildHexahedron(const Vec3& center, float radius, const Vec3& color) {
    const std::vector<Vec3> vertices = {
        Vec3(-1.0f, -1.0f, -1.0f),  // 0
        Vec3(1.0f, -1.0f, -1.0f),   // 1
        Vec3(1.0f, 1.0f, -1.0f),    // 2
        Vec3(-1.0f, 1.0f, -1.0f),   // 3
        Vec3(-1.0f, -1.0f, 1.0f),   // 4
        Vec3(1.0f, -1.0f, 1.0f),    // 5
        Vec3(1.0f, 1.0f, 1.0f),     // 6
        Vec3(-1.0f, 1.0f, 1.0f),    // 7
    };

    const std::vector<std::array<int, 3>> faces = {
        {0, 1, 2}, {0, 2, 3},
        {4, 6, 5}, {4, 7, 6},
        {0, 4, 5}, {0, 5, 1},
        {1, 5, 6}, {1, 6, 2},
        {2, 6, 7}, {2, 7, 3},
        {3, 7, 4}, {3, 4, 0},
    };

    return BuildFromIndexedFaces(vertices, faces, center, radius, color);
}

std::vector<Triangle> BuildIcosahedron(const Vec3& center, float radius, const Vec3& color) {
    const float phi = (1.0f + std::sqrt(5.0f)) * 0.5f;
    const std::vector<Vec3> vertices = {
        Vec3(-1, phi, 0), Vec3(1, phi, 0), Vec3(-1, -phi, 0), Vec3(1, -phi, 0),
        Vec3(0, -1, phi), Vec3(0, 1, phi), Vec3(0, -1, -phi), Vec3(0, 1, -phi),
        Vec3(phi, 0, -1), Vec3(phi, 0, 1), Vec3(-phi, 0, -1), Vec3(-phi, 0, 1),
    };

    const std::vector<std::array<int, 3>> faces = {
        {0, 11, 5}, {0, 5, 1}, {0, 1, 7}, {0, 7, 10}, {0, 10, 11},
        {1, 5, 9}, {5, 11, 4}, {11, 10, 2}, {10, 7, 6}, {7, 1, 8},
        {3, 9, 4}, {3, 4, 2}, {3, 2, 6}, {3, 6, 8}, {3, 8, 9},
        {4, 9, 5}, {2, 4, 11}, {6, 2, 10}, {8, 6, 7}, {9, 8, 1},
    };

    return BuildFromIndexedFaces(vertices, faces, center, radius, color);
}

}  // namespace

std::vector<Triangle> BuildPolyhedronMesh(PolyhedronType type, const Vec3& center, float radius, const Vec3& color) {
    switch (type) {
        case PolyhedronType::Tetrahedron:
            return BuildTetrahedron(center, radius, color);
        case PolyhedronType::Hexahedron:
            return BuildHexahedron(center, radius, color);
        case PolyhedronType::Icosahedron:
            return BuildIcosahedron(center, radius, color);
    }
    return {};
}

}  // namespace kp::domain

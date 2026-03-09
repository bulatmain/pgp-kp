#include "adapters/file/ppm_writer.h"

#include <fstream>

namespace kp::adapters::file {

bool PpmWriter::write(const std::string& path, const kp::domain::Image& image) {
    std::ofstream out(path, std::ios::binary);
    if (!out) {
        return false;
    }

    out << "P6\n" << image.width << ' ' << image.height << "\n255\n";

    for (const kp::domain::Vec3& c : image.pixels) {
        const float r = kp::domain::clamp(c.x, 0.0f, 1.0f);
        const float g = kp::domain::clamp(c.y, 0.0f, 1.0f);
        const float b = kp::domain::clamp(c.z, 0.0f, 1.0f);

        const unsigned char rr = static_cast<unsigned char>(255.0f * r);
        const unsigned char gg = static_cast<unsigned char>(255.0f * g);
        const unsigned char bb = static_cast<unsigned char>(255.0f * b);

        out.write(reinterpret_cast<const char*>(&rr), 1);
        out.write(reinterpret_cast<const char*>(&gg), 1);
        out.write(reinterpret_cast<const char*>(&bb), 1);
    }

    return static_cast<bool>(out);
}

}  // namespace kp::adapters::file

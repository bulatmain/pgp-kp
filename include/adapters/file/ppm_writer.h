#pragma once

#include "ports/image_writer.h"

namespace kp::adapters::file {

class PpmWriter final : public kp::ports::IImageWriter {
public:
    bool write(const std::string& path, const kp::domain::Image& image) override;
};

}  // namespace kp::adapters::file

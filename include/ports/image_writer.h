#pragma once

#include <string>

#include "domain/scene.h"

namespace kp::ports {

class IImageWriter {
public:
    virtual ~IImageWriter() = default;
    virtual bool Write(const std::string& path, const kp::domain::Image& image) = 0;
};

}  // namespace kp::ports

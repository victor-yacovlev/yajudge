#pragma once

#include "Properties.h"

#include <Poco/Util/ServerApplication.h>

namespace Grader {

class Application : public Poco::Util::ServerApplication { 
    Properties::GraderConfig m_config;

    void initialize();
    void defineOptions(Poco::Util::OptionSet& options);
    void handleHelp(const std::string &name, const std::string &value);
};

}
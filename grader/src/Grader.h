#pragma once

#include <Poco/Logger.h>
#include <Poco/Util/Application.h>
#include <Poco/Util/ServerApplication.h>

#include "RPC.h"

namespace Grader {

class Application : public Poco::Util::ServerApplication {
    RPC::RPCProperties _rpcProperties;

    void initialize(Poco::Util::Application& self);
    int main(const std::vector<std::string>& args);

    void defineOptions(Poco::Util::OptionSet& options);
    void handleHelpOption(const std::string& name, const std::string& value);
    void handleConfigOption(const std::string& name, const std::string& value);

    void setupLogger();
    void setupRPCProperties();
};

} // namespace Grader
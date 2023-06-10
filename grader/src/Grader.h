#pragma once

#include <Poco/AutoPtr.h>
#include <Poco/Logger.h>
#include <Poco/TaskManager.h>
#include <Poco/ThreadPool.h>
#include <Poco/Util/Application.h>
#include <Poco/Util/ServerApplication.h>

#include <memory>
#include <string>

namespace Grader {

class Application : public Poco::Util::ServerApplication {
    Poco::ThreadPool _threadPool;
    Poco::TaskManager _taskManager;
    Poco::Task* _gRPCFetcher; // do not use smart pointer here

    void initialize(Poco::Util::Application& self);
    int main(const std::vector<std::string>& args);

    void defineOptions(Poco::Util::OptionSet& options);
    void handleHelpOption(const std::string& name, const std::string& value);
    void handleConfigOption(const std::string& name, const std::string& value);

    void setupLogger();
    void setupThreadPool();
    void setupGRPCFetcherTask();

public:
    explicit Application();
};

} // namespace Grader
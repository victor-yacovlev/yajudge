#include "Grader.h"
#include "RPC.h"

#include <Poco/AutoPtr.h>
#include <Poco/Channel.h>
#include <Poco/ConsoleChannel.h>
#include <Poco/Environment.h>
#include <Poco/FileChannel.h>
#include <Poco/Foundation.h>
#include <Poco/Logger.h>
#include <Poco/NullChannel.h>
#include <Poco/ThreadPool.h>
#include <Poco/Util/HelpFormatter.h>
#include <Poco/Util/JSONConfiguration.h>
#include <Poco/Util/Option.h>
#include <Poco/Util/RegExpValidator.h>

#include <cstdlib>
#ifdef POCO_OS_FAMILY_UNIX
namespace posix {
#include <unistd.h>
}
#endif

#include "Util.h"

void Grader::Application::initialize(Poco::Util::Application& self)
{
    ServerApplication::loadConfiguration();
    ServerApplication::initialize(self);

    try {
        setupLogger();
        setupThreadPool();
        setupGRPCFetcherTask();
    } catch (Poco::Exception& e) {
        Poco::Logger::root().fatal("Grader initialization failed: " + e.message());
        std::exit(1);
    }

    Poco::Logger::root().information("Grader initialized");
}

void Grader::Application::defineOptions(Poco::Util::OptionSet& options)
{
    using Poco::Util::Option, Poco::Util::OptionCallback;

    ServerApplication::defineOptions(options);

    options.addOption(Option("help", "h", "Display help information")
                          .required(false)
                          .repeatable(false)
                          .callback(OptionCallback<Grader::Application>(this, &Grader::Application::handleHelpOption)));

    options.addOption(Option("config", "C", "Config file path")
                          .required(true)
                          .repeatable(false)
                          .argument("file")
                          .callback(OptionCallback<Grader::Application>(this, &Grader::Application::handleConfigOption)));

    options.addOption(Option("name", "N", "Instance name").required(false).repeatable(false).argument("string").binding("instance.name"));

    options.addOption(
        Option("log-path", "L", "Logger output file name").required(false).repeatable(false).argument("out").binding("log.path"));

    options.addOption(Option("log-level", "l", "Logger details level")
                          .required(false)
                          .repeatable(false)
                          .argument("level")
                          .binding("log.level")
                          .validator(new Poco::Util::RegExpValidator("none|fatal|critical|error|warning|notice|"
                                                                     "information|debug|trace")));
}

int Grader::Application::main(const std::vector<std::string>& args)
{
    const std::string message = std::string("Started grader service at pid=") + std::to_string(posix::getpid());
    Poco::Logger::root().information(message);
    _taskManager.start(_gRPCFetcher);
    _taskManager.joinAll();
    return 0;
}

void Grader::Application::handleHelpOption(const std::string& name, const std::string& value)
{
    Poco::Util::HelpFormatter helpFormatter(options());
    helpFormatter.setCommand(commandName());
    helpFormatter.setUsage("OPTIONS");
    helpFormatter.format(std::cout);
    stopOptionsProcessing();
    std::exit(0);
}

void Grader::Application::handleConfigOption(const std::string& name, const std::string& value)
{
    auto conf = new Util::YAMLConfiguration();
    try {
        conf->load(value);
        config().add(Poco::AutoPtr<Poco::Util::AbstractConfiguration>(conf));
        config().setString("config.path", Poco::Path(value).absolute().toString());
    } catch (std::exception& e) {
        Poco::Logger::root().fatal(std::string("Can't process YAML config file: ") + e.what());
        std::exit(1);
    }
}

void Grader::Application::setupLogger()
{
    const std::string logLevel = config().getString("log.level", "information");
    const std::string logPath = config().getString("log.path", "stdout");

    Poco::Logger& root = Poco::Logger::root();

    root.setLevel(logLevel);

    Poco::AutoPtr<Poco::Channel> pChannel;

    if ("none" == logLevel) {
        pChannel = new Poco::NullChannel;
    } else if ("stdout" == logPath) {
        pChannel = new Poco::ConsoleChannel(std::cout);
    } else if ("stderr" == logPath) {
        pChannel = new Poco::ConsoleChannel(std::cerr);
    } else {
        pChannel = new Poco::FileChannel(logPath);
    }

    root.information("Logger configured, next messages will be in %s", logPath);
    root.setChannel(pChannel);
}

void Grader::Application::setupThreadPool()
{
    const int workersCount = config().getInt("jobs.workers", 0);
    // thread pool size must have +1 slot for gRPC task
    const int threadPoolSize = workersCount > 0 ? workersCount + 1 : _threadPool.capacity();
    const int capacityDiff = threadPoolSize - _threadPool.capacity();
    _threadPool.addCapacity(capacityDiff);
}

void Grader::Application::setupGRPCFetcherTask()
{
    // prepare fetcher task that will be started on application run
    // NOTE: do not use smart pointers or manual delete. Task manager will free memory for us
    _gRPCFetcher = new RPC::GRPCFetcherTask(config(), _threadPool, _taskManager);
}

Grader::Application::Application()
    : ServerApplication()
    , _taskManager(_threadPool)
{
}

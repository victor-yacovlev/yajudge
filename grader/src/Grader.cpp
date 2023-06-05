#include "Grader.h"

#include <Poco/Util/HelpFormatter.h>
#include <Poco/Util/Option.h>
#include <Poco/Util/RegExpValidator.h>

#include <cstdlib>

void Grader::Application::initialize()
{

}

void Grader::Application::defineOptions(Poco::Util::OptionSet& options)
{
    using Poco::Util::Option, Poco::Util::OptionCallback;
    
    ServerApplication::defineOptions(options);

    options.addOption(
        Option("help", "h", "display help information")
        .required(false)
        .repeatable(false)
        .callback(OptionCallback<Grader::Application>(this, &Grader::Application::handleHelp))
    );

    options.addOption(
        Option("config", "C", "config file path")
        .required(true)
        .repeatable(false)
        .binding("config.path")
    );

    options.addOption(
        Option("log-path", "L", "logger output file name")
        .required(false)
        .repeatable(false)
        .binding("log.path")
    );

    options.addOption(
        Option("log-level", "l", "logger details level")
        .required(false)
        .repeatable(false)
        .binding("log.level")
        .validator(new Poco::Util::RegExpValidator(
            "none|fatal|critical|error|warning|notice|information|debug|trace"
        ))
    );
}

void Grader::Application::handleHelp(const std::string& name, const std::string& value)
{
    Poco::Util::HelpFormatter helpFormatter(options());
    helpFormatter.setCommand(commandName());
    helpFormatter.setUsage("OPTIONS");
    helpFormatter.format(std::cout);
    std::exit(0);
}

#include "Properties.h"
#include "Util.h"

#include <Poco/FileStream.h>
#include <Poco/Path.h>
#include <Poco/StreamCopier.h>
#include <Poco/String.h>
#include <yaml-cpp/yaml.h>

namespace posix {
#include <sys/stat.h>
}

template <typename T> static void updateValueFromOtherIfNotDefault(const T& newValue, T& oldValue)
{
    const T defaultValue = T();
    if (defaultValue != newValue) {
        oldValue = newValue;
    }
}

static void updateValueFromOtherIfNotDefault(const Poco::Path& newValue, Poco::Path& oldValue)
{
    if (!newValue.toString().empty()) {
        oldValue = newValue;
    }
}

Properties::Limits& Properties::Limits::updateFrom(const Properties::Limits& other)
{
    updateValueFromOtherIfNotDefault(other.stackSizeLimitMb, stackSizeLimitMb);
    updateValueFromOtherIfNotDefault(other.memoryMaxLimitMb, memoryMaxLimitMb);
    updateValueFromOtherIfNotDefault(other.cpuTimeLimitSec, cpuTimeLimitSec);
    updateValueFromOtherIfNotDefault(other.realTimeLimitSec, realTimeLimitSec);
    updateValueFromOtherIfNotDefault(other.procCountLimit, procCountLimit);
    updateValueFromOtherIfNotDefault(other.fdCountLimit, fdCountLimit);
    updateValueFromOtherIfNotDefault(other.stdoutSizeLimitMb, stdoutSizeLimitMb);
    updateValueFromOtherIfNotDefault(other.stderrSizeLimitMb, stderrSizeLimitMb);
    updateValueFromOtherIfNotDefault(other.allowNetwork, allowNetwork);
    return *this;
}

Properties::Limits Properties::Limits::fromProtobuf(const yajudge::GradingLimits* proto)
{
    Limits result;
    result.stackSizeLimitMb = proto->stack_size_limit_mb();
    result.memoryMaxLimitMb = proto->memory_max_limit_mb();
    result.cpuTimeLimitSec = proto->cpu_time_limit_sec();
    result.realTimeLimitSec = proto->real_time_limit_sec();
    result.procCountLimit = proto->proc_count_limit();
    result.fdCountLimit = proto->fd_count_limit();
    result.stdoutSizeLimitMb = proto->stdout_size_limit_mb();
    result.stderrSizeLimitMb = proto->stderr_size_limit_mb();
    result.allowNetwork = proto->allow_network();
    return result;
}

Properties::Endpoints Properties::Endpoints::fromConfig(const Poco::Path& confPath, const Poco::Util::AbstractConfiguration::Ptr& config)
{
    Endpoints result;
    result.courseContentProvider = Poco::URI(config->getString("courses_content"));
    resolveFullURI(result.courseContentProvider, confPath);
    result.submissionManagement = Poco::URI(config->getString("submissions"));
    resolveFullURI(result.submissionManagement, confPath);
    return result;
}

void Properties::Endpoints::validate() const
{
    validateURI(courseContentProvider);
    validateURI(submissionManagement);
}

void Properties::Endpoints::resolveFullURI(Poco::URI& uri, const Poco::Path& confPath)
{
    if (uri.getScheme() == "grpc") {
        uri.setScheme("http");
    } else if (uri.getScheme() == "grpcs") {
        uri.setScheme("https");
    }

    if (uri.getScheme() == "unix") {
        // full URI provided, so path is absolute and do nothing in this case
    } else if (uri.getScheme() == "http" && uri.getPort() == 0) {
        uri.setPort(80);
    } else if (uri.getScheme() == "https" && uri.getPort() == 0) {
        uri.setPort(443);
    } else if (uri.getScheme().empty()) {
        // possible local file name
        Poco::Path path = uri.getPath();
        if (path.isAbsolute()) {
            return; // nothing to resolve
        }
        path = confPath.parent().resolve(uri.getPath());
        uri.setPath(path.toString());
        uri.setScheme("unix");
    }
}

void Properties::Endpoints::validateURI(const Poco::URI& uri)
{
    if (uri.getScheme() == "unix") {
        struct posix::stat st;
        if (-1 == posix::stat(uri.getPath().c_str(), &st)) {
            throw Poco::PathNotFoundException("Unix socket file not found", uri.getPath());
        }
        if (!S_ISSOCK(st.st_mode)) {
            throw Poco::PathNotFoundException("Not a unix socket file %s", uri.getPath());
        }
    } else if (uri.getScheme() == "http" || uri.getScheme() == "https") {
        if (uri.getHost().empty()) {
            throw Poco::DataException("No host name set for endpoint");
        }
    } else {
        throw Poco::DataException("Unknown URI scheme %s for endpoint", uri.getScheme());
    }
}

Properties::RPC Properties::RPC::fromConfig(const Poco::Path& confPath, const Poco::Util::AbstractConfiguration::Ptr& config)
{
    RPC result;
    result.endpoints = Endpoints::fromConfig(confPath, config->createView("endpoints"));
    if (config->has("private_token_file")) {
        const std::string privateTokenPathString = config->getString("private_token_file");
        const auto path = Util::expandRelativePath(confPath, config->getString("private_token_file"));
        Poco::FileStream ifs(path.toString());
        Poco::StreamCopier::copyToString(ifs, result.privateToken);
    } else if (config->has("private_token")) {
        const std::string privateToken = config->getString("private_token");
        result.privateToken = privateToken;
    }
    Poco::trimInPlace(result.privateToken);
    return result;
}

void Properties::RPC::validate() const
{
    endpoints.validate();
    if (privateToken.empty()) {
        throw Poco::DataException("No private toket set in RPC configuration");
    }
}

Properties::Locations Properties::Locations::fromConfig(const Poco::Path& confPath, const Poco::Util::AbstractConfiguration::Ptr& config)
{
    Locations result;
    result.workDirectory = Util::expandRelativePath(confPath, config->getString("working_directory", ""));
    result.cacheDirectory = Util::expandRelativePath(confPath, config->getString("cache_directory", ""));
    result.systemRoot = Util::expandRelativePath(confPath, config->getString("system_environment", ""));
    return result;
}

void Properties::Locations::validate() const
{
    if (workDirectory.toString().empty()) {
        throw Poco::DataException("Working directory not set in config");
    }
    if (cacheDirectory.toString().empty()) {
        throw Poco::DataException("Cache directory not set in config");
    }
    if (!Util::isWritableDirectory(workDirectory)) {
        throw Poco::FileException("Working directory is not writable or not exits: %s", workDirectory.toString());
    }
    if (!Util::isWritableDirectory(cacheDirectory)) {
        throw Poco::FileException("Cache directory is not writable or not exits: %s", cacheDirectory.toString());
    }
}

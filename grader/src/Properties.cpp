#include "Properties.h"

#include <Poco/FileStream.h>
#include <Poco/Path.h>
#include <Poco/String.h>
#include <yaml-cpp/yaml.h>

static Poco::Path getSubConfigFilePath(const Poco::Path& rootFilePath, const std::string& relPath)
{
    if (relPath.empty()) {
        return rootFilePath.absolute();
    }
    if (relPath[0] == '/') {
        return Poco::Path(relPath); // path is absolute
    }
    Poco::Path parent = rootFilePath.absolute();
    parent.makeParent();
    return parent.resolve(relPath);
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
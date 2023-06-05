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

template <typename T>
static void updateValueFromNodeIfDefined(const YAML::Node& yamlNode, const char* key, T& value)
{
    if (yamlNode.IsMap() && yamlNode[key].IsDefined()) {
        value = yamlNode[key].as<T>();
    }
}

template <typename T>
static void updateValueFromOtherIfNotDefault(const T& newValue, T& oldValue)
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

Properties::GraderConfig Properties::GraderConfig::fromYAMLFile(const Poco::Path& configFilePath)
{
    YAML::Node yamlRoot = YAML::LoadFile(configFilePath.toString());
    YAML::Node yamlRpc = yamlRoot["rpc"];
    YAML::Node yamlLocations = yamlRoot["locations"];
    YAML::Node yamlJobs = yamlRoot["jobs"];
    GraderConfig result;
    result.rpc = Rpc::fromYAMLNode(configFilePath, yamlRpc);
    result.locations = Locations::fromYAMLNode(configFilePath, yamlLocations);
    result.jobs = Jobs::fromYAMLNode(configFilePath, yamlJobs);
    return result;
}

Properties::GraderConfig& Properties::GraderConfig::updateFrom(const GraderConfig& other)
{
    rpc.updateFrom(other.rpc);
    locations.updateFrom(other.locations);
    jobs.updateFrom(other.jobs);
    return *this;
}

Properties::Locations Properties::Locations::fromYAMLNode(const Poco::Path& rootFilePath, const YAML::Node& yamlNode)
{
    Locations result;
    const YAML::Node yamlSystemEnvironment = yamlNode["system_environment"];
    const YAML::Node yamlWorkingDirectory = yamlNode["working_directory"];
    const YAML::Node yamlCacheDirectory = yamlNode["cache_directory"];
    if (yamlSystemEnvironment.IsDefined()) {
        result.systemRoot = getSubConfigFilePath(rootFilePath, yamlSystemEnvironment.as<std::string>());
    }
    if (yamlWorkingDirectory.IsDefined()) {
        result.workDirectory = getSubConfigFilePath(rootFilePath, yamlWorkingDirectory.as<std::string>());
    }
    if (yamlCacheDirectory.IsDefined()) {
        result.cacheDirectory = getSubConfigFilePath(rootFilePath, yamlCacheDirectory.as<std::string>());
    }
    return result;
}

Properties::Locations& Properties::Locations::updateFrom(const Properties::Locations& other)
{
    if (!other.systemRoot.toString().empty()) {
        systemRoot = other.systemRoot;
    }
    if (!other.workDirectory.toString().empty()) {
        workDirectory = other.workDirectory;
    }
    if (!other.cacheDirectory.toString().empty()) {
        cacheDirectory = other.cacheDirectory;
    }
    return *this;
}

Properties::Rpc Properties::Rpc::fromYAMLNode(const Poco::Path& rootFilePath, const YAML::Node& yamlNode)
{
    if (yamlNode.IsNull()) {
        return Rpc();
    }
    Rpc result;
    const YAML::Node yamlEndpoints = yamlNode["endpoints"];
    if (yamlEndpoints.IsScalar()) {
        const std::string relativeFileName = yamlEndpoints.as<std::string>();
        const Poco::Path absFileName = getSubConfigFilePath(rootFilePath, relativeFileName);
        result.endpoints = Endpoints::fromYAMLFile(absFileName);
    } else if (yamlEndpoints.IsMap()) {
        result.endpoints = Endpoints::fromYAMLNode(rootFilePath, yamlEndpoints);
    }
    const YAML::Node yamlPrivateTokenFile = yamlNode["private_token_file"];
    if (yamlPrivateTokenFile.IsDefined()) {
        // private token stored in dedicated file
        std::string relativeFileName = yamlPrivateTokenFile.as<std::string>();
        Poco::Path absFileName = getSubConfigFilePath(rootFilePath, relativeFileName);
        Poco::FileInputStream inputStream(absFileName.toString());
        char buffer[1024] = {};
        inputStream.getline(buffer, sizeof(buffer));
        result.privateToken = std::string(buffer);
        Poco::trimInPlace(result.privateToken);
    }
    const YAML::Node yamlPrivateToken = yamlNode["private_token"];
    if (yamlPrivateToken.IsDefined()) {
        result.privateToken = yamlPrivateToken.as<std::string>();
    }
    return result;
}

Properties::Rpc& Properties::Rpc::updateFrom(const Properties::Rpc& other)
{
    updateValueFromOtherIfNotDefault(other.privateToken, privateToken);
    endpoints.updateFrom(other.endpoints);
    return *this;
}

Properties::Endpoints Properties::Endpoints::fromYAMLNode(const Poco::Path& rootFilePath, const YAML::Node& yamlNode)
{
    Endpoints result;
    const YAML::Node yamlCourseContentProvider = yamlNode["yajudge.CourseContentProvider"];
    const YAML::Node yamlSubmissionManagement = yamlNode["yajudge.SubmissionManagement"];
    if (yamlCourseContentProvider.IsDefined()) {
        result.courseContentProvider = Poco::URI(yamlCourseContentProvider.as<std::string>());
    }
    if (yamlSubmissionManagement.IsDefined()) {
        result.submissionManagement = Poco::URI(yamlSubmissionManagement.as<std::string>());
    }
    return result;
}

Properties::Endpoints Properties::Endpoints::fromYAMLFile(const Poco::Path& configFilePath)
{
    const YAML::Node root = YAML::LoadFile(configFilePath.toString());
    return Endpoints::fromYAMLNode(configFilePath, root);
}

Properties::Endpoints& Properties::Endpoints::updateFrom(const Properties::Endpoints& other)
{
    if (!other.courseContentProvider.empty()) {
        courseContentProvider = other.courseContentProvider;
    }
    if (!other.submissionManagement.empty()) {
        submissionManagement = other.submissionManagement;
    }
    return *this;
}

Properties::Jobs Properties::Jobs::fromYAMLNode(const Poco::Path& rootFilePath, const YAML::Node& yamlNode)
{
    Jobs result;
    updateValueFromNodeIfDefined(yamlNode, "arch_specific_only", result.archSpecificOnly);
    updateValueFromNodeIfDefined(yamlNode, "workers", result.workers);
    return result;
}

Properties::Jobs& Properties::Jobs::updateFrom(const Properties::Jobs& other)
{
    updateValueFromOtherIfNotDefault(other.archSpecificOnly, archSpecificOnly);
    updateValueFromOtherIfNotDefault(other.workers, workers);
    return *this;
}

Properties::Log Properties::Log::fromYAMLNode(const Poco::Path& rootFilePath, const YAML::Node& yamlNode)
{
    Log result;
    const YAML::Node yamlPath = yamlNode["path"];
    if (yamlPath.IsDefined()) {
        result.path = getSubConfigFilePath(rootFilePath, yamlPath.as<std::string>());
    }
    updateValueFromNodeIfDefined(yamlNode, "level", result.level);
    Poco::toLowerInPlace(result.level);
    return result;
}

Properties::Log& Properties::Log::updateFrom(const Properties::Log& other)
{
    updateValueFromOtherIfNotDefault(other.path, path);
    updateValueFromOtherIfNotDefault(other.level, level);
    return *this;
}

Properties::Limits Properties::Limits::fromYAMLFile(const Poco::Path& configFilePath)
{
    const YAML::Node rootNode = YAML::LoadFile(configFilePath.toString());
    return Limits::fromYAMLNode(configFilePath, rootNode);
}

Properties::Limits Properties::Limits::fromYAMLNode(const Poco::Path& rootFilePath, const YAML::Node& yamlNode)
{
    Limits result;
    updateValueFromNodeIfDefined(yamlNode, "stack_size_limit_mb", result.stackSizeLimitMb);
    updateValueFromNodeIfDefined(yamlNode, "memory_max_limit_mb", result.memoryMaxLimitMb);
    updateValueFromNodeIfDefined(yamlNode, "cpu_time_limit_sec", result.cpuTimeLimitSec);
    updateValueFromNodeIfDefined(yamlNode, "real_time_limit_sec", result.realTimeLimitSec);
    updateValueFromNodeIfDefined(yamlNode, "proc_count_limit", result.procCountLimit);
    updateValueFromNodeIfDefined(yamlNode, "fd_count_limit", result.fdCountLimit);
    updateValueFromNodeIfDefined(yamlNode, "stdout_size_limit_mb", result.stdoutSizeLimitMb);
    updateValueFromNodeIfDefined(yamlNode, "stderr_size_limit_mb", result.stderrSizeLimitMb);
    updateValueFromNodeIfDefined(yamlNode, "allow_network", result.allowNetwork);
    return result;
}

void Properties::Limits::toYAMLFile(const Poco::Path& filePath)
{
    Poco::FileOutputStream stream(filePath.toString());
    stream << "stack_size_limit_mb: " << stackSizeLimitMb << std::endl;
    stream << "memory_max_limit_mb: " << memoryMaxLimitMb << std::endl;
    stream << "cpu_time_limit_sec: " << cpuTimeLimitSec << std::endl;
    stream << "real_time_limit_sec: " << realTimeLimitSec << std::endl;
    stream << "proc_count_limit: " << procCountLimit << std::endl;
    stream << "fd_count_limit: " << fdCountLimit << std::endl;
    stream << "stdout_size_limit_mb: " << stdoutSizeLimitMb << std::endl;
    stream << "stderr_size_limit_mb: " << stderrSizeLimitMb << std::endl;
    stream << "allow_network: " << allowNetwork << std::endl;
    stream.close();
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
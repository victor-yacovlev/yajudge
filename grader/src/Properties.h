#pragma once

#include "yajudge_common.pb.h"

#include <Poco/Exception.h>
#include <Poco/Path.h>
#include <Poco/URI.h>
#include <yaml-cpp/yaml.h>

#include <map>
#include <string>

namespace Properties {

struct Log {
    std::string level;
    Poco::Path path;

    static Log fromYAMLNode(const Poco::Path& rootFilePath, const YAML::Node& yamlNode);
    Log& updateFrom(const Log& other);
};

struct Endpoints {
    Poco::URI courseContentProvider;
    Poco::URI submissionManagement;

    static Endpoints fromYAMLNode(const Poco::Path& rootFilePath, const YAML::Node& yamlNode);
    static Endpoints fromYAMLFile(const Poco::Path& configFilePath);
    Endpoints& updateFrom(const Endpoints& other);
};

struct Rpc {
    Endpoints endpoints;
    std::string privateToken;

    static Rpc fromYAMLNode(const Poco::Path& rootFilePath, const YAML::Node& yamlNode);
    Rpc& updateFrom(const Rpc& other);
};

struct Locations {
    Poco::Path systemRoot;
    Poco::Path workDirectory;
    Poco::Path cacheDirectory;

    static Locations fromYAMLNode(const Poco::Path& rootFilePath, const YAML::Node& yamlNode);
    Locations& updateFrom(const Locations& other);
};

struct Jobs {
    bool archSpecificOnly = false;
    int workers = 0;

    static Jobs fromYAMLNode(const Poco::Path& rootFilePath, const YAML::Node& yamlNode);
    Jobs& updateFrom(const Jobs& other);
};

struct GraderConfig {
    Rpc rpc;
    Locations locations;
    Jobs jobs;
    Log log;
    std::string name = "default";

    static GraderConfig fromYAMLFile(const Poco::Path& configFilePath);
    GraderConfig& updateFrom(const GraderConfig& other);
};

struct Limits {
    int stackSizeLimitMb = 4;
    int memoryMaxLimitMb = 64;
    int cpuTimeLimitSec = 1;
    int realTimeLimitSec = 5;
    int procCountLimit = 20;
    int fdCountLimit = 20;
    int stdoutSizeLimitMb = 1;
    int stderrSizeLimitMb = 1;
    bool allowNetwork = false;

    static Limits fromYAMLFile(const Poco::Path& configFilePath);
    static Limits fromYAMLNode(const Poco::Path& rootFilePath, const YAML::Node& yamlNode);
    static Limits fromProtobuf(const yajudge::GradingLimits* proto);
    Limits& updateFrom(const Limits& other);
    void toYAMLFile(const Poco::Path& filePath);
};

} // namespace Properties
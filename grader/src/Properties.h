#pragma once

#include <Poco/Exception.h>
#include <Poco/Path.h>
#include <Poco/URI.h>
#include <Poco/Util/ConfigurationView.h>

#include <map>
#include <string>

#include "yajudge_common.pb.h"

namespace Properties {

struct Locations {
    Poco::Path systemRoot;
    Poco::Path workDirectory;
    Poco::Path cacheDirectory;

    static Locations fromConfig(const Poco::Path& confPath, const Poco::Util::AbstractConfiguration::Ptr& config);
    void validate() const;
};

struct Jobs {
    bool archSpecificOnly = false;
    int workers = 0;
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

    static Limits fromProtobuf(const yajudge::GradingLimits* proto);
    Limits& updateFrom(const Limits& other);
};

struct Endpoints {
    Poco::URI courseContentProvider;
    Poco::URI submissionManagement;

    static Endpoints fromConfig(const Poco::Path& confPath, const Poco::Util::AbstractConfiguration::Ptr& config);
    void validate() const;

private:
    static void resolveFullURI(Poco::URI& uri, const Poco::Path& confPath);
    static void validateURI(const Poco::URI& uri);
};

struct RPC {
    Endpoints endpoints;
    std::string privateToken;

    static RPC fromConfig(const Poco::Path& confPath, const Poco::Util::AbstractConfiguration::Ptr& config);
    void validate() const;
};

} // namespace Properties
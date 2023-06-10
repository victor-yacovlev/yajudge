#pragma once

#include <Poco/Path.h>
#include <Poco/URI.h>
#include <Poco/Util/ConfigurationView.h>

#include <string>

namespace RPC {

struct EndpointsProperties {
    Poco::URI courseContentProvider;
    Poco::URI submissionManagement;

    static EndpointsProperties fromConfig(const Poco::Path& confPath, const Poco::Util::AbstractConfiguration::Ptr& config);
    void validate();

private:
    static void resolveFullURI(Poco::URI& uri, const Poco::Path& confPath);
    static void validateURI(const Poco::URI& uri);
};

struct RPCProperties {
    EndpointsProperties endpoints;
    std::string privateToken;

    static RPCProperties fromConfig(const Poco::Path& confPath, const Poco::Util::AbstractConfiguration::Ptr& config);
    void validate();
};

} // namespace RPC
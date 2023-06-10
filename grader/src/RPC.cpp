#include "RPC.h"

#include <Poco/FileStream.h>
#include <Poco/Path.h>
#include <Poco/StreamCopier.h>
#include <Poco/String.h>

namespace posix {
#include <sys/stat.h>
}

RPC::EndpointsProperties RPC::EndpointsProperties::fromConfig(
    const Poco::Path& confPath, const Poco::Util::AbstractConfiguration::Ptr& config)
{
    EndpointsProperties result;
    result.courseContentProvider = Poco::URI(config->getString("courses_content"));
    resolveFullURI(result.courseContentProvider, confPath);
    result.submissionManagement = Poco::URI(config->getString("submissions"));
    resolveFullURI(result.submissionManagement, confPath);
    return result;
}

void RPC::EndpointsProperties::validate()
{
    validateURI(courseContentProvider);
    validateURI(submissionManagement);
}

void RPC::EndpointsProperties::resolveFullURI(Poco::URI& uri, const Poco::Path& confPath)
{
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

void RPC::EndpointsProperties::validateURI(const Poco::URI& uri)
{
    if (uri.getScheme() == "unix") {
        struct posix::stat st;
        if (-1 == posix::stat(uri.getPath().c_str(), &st)) {
            throw Poco::PathNotFoundException("Unix socket file not found", uri.getPath());
        }
        if (!S_ISSOCK(st.st_mode)) {
            throw Poco::PathNotFoundException("Not a unix socket file %s", uri.getPath());
        }
    } else {
        if (uri.getHost().empty()) {
            throw Poco::DataException("No host name set for endpoint");
        }
    }
}

RPC::RPCProperties RPC::RPCProperties::fromConfig(const Poco::Path& confPath, const Poco::Util::AbstractConfiguration::Ptr& config)
{
    RPCProperties result;
    result.endpoints = EndpointsProperties::fromConfig(confPath, config->createView("endpoints"));
    if (config->has("private_token_file")) {
        const std::string privateTokenPathString = config->getString("private_token_file");
        Poco::Path path(privateTokenPathString);
        if (path.isRelative()) {
            path = confPath.parent();
            path.resolve(privateTokenPathString);
        }
        Poco::FileStream ifs(path.toString());
        Poco::StreamCopier::copyToString(ifs, result.privateToken);
    } else if (config->has("private_token")) {
        const std::string privateToken = config->getString("private_token");
        result.privateToken = privateToken;
    }
    Poco::trimInPlace(result.privateToken);
    return result;
}

void RPC::RPCProperties::validate()
{
    endpoints.validate();
    if (privateToken.empty()) {
        throw Poco::DataException("No private toket set in RPC configuration");
    }
}

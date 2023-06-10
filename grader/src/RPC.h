#pragma once

#include "Properties.h"

#include "yajudge_courses_content.grpc.pb.h"
#include "yajudge_submissions.grpc.pb.h"

#include <grpcpp/grpcpp.h>

#include <Poco/Logger.h>
#include <Poco/Path.h>
#include <Poco/Task.h>
#include <Poco/TaskManager.h>
#include <Poco/URI.h>
#include <Poco/Util/AbstractConfiguration.h>

namespace RPC {

class GRPCFetcherTask : public Poco::Task {
    const Properties::RPC _rpcProperties;
    const Properties::Locations _locationsProperties;
    Poco::Logger& _log;
    const yajudge::ConnectedServiceProperties _greetingProperties;
    Poco::ThreadPool& _threadPool;
    Poco::TaskManager& _taskManager;

    std::unique_ptr<yajudge::SubmissionManagement::Stub> _submissionManagementService;
    std::unique_ptr<yajudge::CourseContentProvider::Stub> _contentProviderService;
    std::unique_ptr<grpc::ClientReader<yajudge::Submission>> _masterStream;

    static yajudge::ConnectedServiceProperties createGreetingProperties(
        const Poco::Util::AbstractConfiguration& config, const Poco::ThreadPool& threadPool);
    static Properties::RPC createRPCProperties(const Poco::Util::AbstractConfiguration& config);
    static Properties::Locations createLocationsProperties(const Poco::Util::AbstractConfiguration& config);
    void runTask() override;
    void serveConnection();
    void connectToServer();
    static std::shared_ptr<grpc::Channel> makeGRPCChannel(const Poco::URI& endpointURI);
    void pushGraderStatus();
    bool canAcceptNewSubmission() const;

public:
    explicit GRPCFetcherTask(Poco::Util::AbstractConfiguration& config, Poco::ThreadPool& threadPool, Poco::TaskManager& taskManager);
};

} // namespace RPC
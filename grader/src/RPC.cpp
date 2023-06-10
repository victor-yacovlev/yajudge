#include "RPC.h"

#include <Poco/Environment.h>
#include <Poco/FileStream.h>
#include <Poco/Foundation.h>
#include <Poco/Logger.h>
#include <Poco/Path.h>
#include <Poco/StreamCopier.h>
#include <Poco/String.h>
#include <Poco/Timestamp.h>

#include <cinttypes>

RPC::GRPCFetcherTask::GRPCFetcherTask(
    Poco::Util::AbstractConfiguration& config, Poco::ThreadPool& threadPool, Poco::TaskManager& taskManager)
    : Poco::Task("gRPC Fetcher")
    , _rpcProperties(createRPCProperties(config))
    , _locationsProperties(createLocationsProperties(config))
    , _log(Poco::Logger::root().get("gRPC Fetcher"))
    , _greetingProperties(createGreetingProperties(config, threadPool))
    , _threadPool(threadPool)
    , _taskManager(taskManager)
{
}

static double estimatePerformanceRating()
{
    // calculate maxPrimesCount prime numbers and measure a time in milliseconds
    // returns 1_000_000/time (higher is better performance)
    const auto maxPrimesCount = 20000;
    int currentPrime = 2;
    int primesFound = 0;
    const auto timestamp = Poco::Timestamp();
    while (primesFound < maxPrimesCount) {
        bool isPrime = true;
        for (int divider = 2; divider < currentPrime; divider++) {
            isPrime = (currentPrime % divider) > 0;
            if (!isPrime) {
                break;
            }
        }
        if (isPrime) {
            primesFound++;
        }
        currentPrime++;
    }
    const auto milliseconds = timestamp.elapsed();
    double result = 1000000.0 / milliseconds;
    return result;
}

yajudge::ConnectedServiceProperties RPC::GRPCFetcherTask::createGreetingProperties(
    const Poco::Util::AbstractConfiguration& config, const Poco::ThreadPool& threadPool)
{
    const std::string instanceName = config.getString("instance.name", "default");
    const std::string name = instanceName + "@" + Poco::Environment::nodeName();
    const bool archSpecificOnly = config.getBool("jobs.arch_specific_only", false);
    const int numberOfWorkers = threadPool.capacity() - 1;

    yajudge::ConnectedServiceProperties result;
    result.set_performance_rating(estimatePerformanceRating());
    result.set_role(yajudge::ServiceRole::SERVICE_GRADING);
    result.set_name(name);
    result.set_arch_specific_only_jobs(archSpecificOnly);
    result.set_number_of_workers(numberOfWorkers);

    yajudge::GradingPlatform* platform = result.mutable_platform();
#ifdef POCO_ARCH_AARCH64
    platform->set_arch(yajudge::Arch::ARCH_AARCH64);
#endif
#ifdef POCO_ARCH_ARM
    platform->set_arch(yajudge::Arch::ARCH_ARMV7);
#endif
#ifdef POCO_ARCH_IA32
    platform->set_arch(yajudge::Arch::ARCH_X86);
#endif
#ifdef POCO_ARCH_AMD64
    platform->set_arch(yajudge::Arch::ARCH_X86_64);
#endif

    return result;
}

Properties::RPC RPC::GRPCFetcherTask::createRPCProperties(const Poco::Util::AbstractConfiguration& config)
{
    const Poco::Path configFilePath(config.getString("config.path"));
    const auto rpcProperties = Properties::RPC::fromConfig(configFilePath, config.createView("rpc"));
    rpcProperties.validate();
    return rpcProperties;
}

Properties::Locations RPC::GRPCFetcherTask::createLocationsProperties(const Poco::Util::AbstractConfiguration& config)
{
    const Poco::Path configFilePath(config.getString("config.path"));
    const auto locationsProperties = Properties::Locations::fromConfig(configFilePath, config.createView("locations"));
    locationsProperties.validate();
    return locationsProperties;
}

void RPC::GRPCFetcherTask::runTask()
{
    while (!isCancelled()) {
        // master server or more likely nginx proxy will close connection
        // by timeout, so make automatic reconnect to master server
        // until not stop requested
        serveConnection();
        if (!isCancelled()) {
            sleep(1000);
        }
    }
}

void RPC::GRPCFetcherTask::serveConnection()
{
    connectToServer();
    pushGraderStatus();

    grpc::ClientContext ctx;
    ctx.AddMetadata("token", _rpcProperties.privateToken);
    _masterStream = _submissionManagementService->ReceiveSubmissionsToProcess(&ctx, _greetingProperties);

    yajudge::Submission submission;
    while (_masterStream->Read(&submission)) {
        const auto logMessage = std::string("Got submission to process: ") + std::to_string((int)submission.id());
        _log.information(logMessage);
    }
}

void RPC::GRPCFetcherTask::connectToServer()
{
    auto submissionChannel = makeGRPCChannel(_rpcProperties.endpoints.submissionManagement);
    auto contentChannel = makeGRPCChannel(_rpcProperties.endpoints.submissionManagement);

    _submissionManagementService = yajudge::SubmissionManagement::NewStub(submissionChannel);
    _contentProviderService = yajudge::CourseContentProvider::NewStub(contentChannel);
}

std::shared_ptr<grpc::Channel> RPC::GRPCFetcherTask::makeGRPCChannel(const Poco::URI& endpointURI)
{
    std::shared_ptr<grpc::ChannelCredentials> credentials;
    std::string target;

    if (endpointURI.getScheme() == "https") {
        credentials = grpc::SslCredentials(grpc::SslCredentialsOptions());
    } else {
        credentials = grpc::InsecureChannelCredentials();
    }

    if (endpointURI.getScheme() == "unix") {
        target = "unix://" + endpointURI.getPath();
    } else {
        target = endpointURI.getHost() + ":" + std::to_string(endpointURI.getPort());
    }

    return grpc::CreateChannel(target, credentials);
}

void RPC::GRPCFetcherTask::pushGraderStatus()
{
    yajudge::ConnectedServiceStatus statusMessage;

    const int capacity = _greetingProperties.number_of_workers();
    const int used = _taskManager.count() - 1;
    const int freeSlots = capacity - used;
    auto status = canAcceptNewSubmission() ? yajudge::ServiceStatus::SERVICE_STATUS_IDLE : yajudge::ServiceStatus::SERVICE_STATUS_BUSY;
    statusMessage.set_status(status);
    statusMessage.set_capacity(freeSlots);
    statusMessage.set_allocated_properties(new yajudge::ConnectedServiceProperties(_greetingProperties));

    grpc::ClientContext ctx;
    ctx.AddMetadata("token", _rpcProperties.privateToken);
    yajudge::Empty response;
    auto grpcStatus = _submissionManagementService->SetExternalServiceStatus(&ctx, statusMessage, &response);
    if (!grpcStatus.ok()) {
        _log.error("Can't push status to master: " + grpcStatus.error_message());
    }
}

bool RPC::GRPCFetcherTask::canAcceptNewSubmission() const
{
    const int capacity = _greetingProperties.number_of_workers();
    const int used = _taskManager.count() - 1;
    const int freeSlots = capacity - used;
    return freeSlots > 0;
}

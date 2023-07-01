use crate::{
    generated::yajudge::{
        course_content_provider_client::CourseContentProviderClient,
        submission_management_client::SubmissionManagementClient, Arch, ConnectedServiceProperties,
        ConnectedServiceStatus, ContentStatus, GradingPlatform, ProblemContentRequest, ServiceRole,
        ServiceStatus, Submission,
    },
    properties::{JobsConfig, RpcConfig},
    storage::StorageManager,
};
use slog::Logger;
use std::{error::Error, str::FromStr, time::Duration};
use tokio::{select, time::sleep};
use tokio_util::sync::CancellationToken;
use tonic::{
    codegen::InterceptedService,
    metadata::MetadataValue,
    service::Interceptor,
    transport::{Channel, Endpoint},
    Code, Status,
};
use uris::Uri;

pub const RECONNECT_TIMEOUT: u64 = 10;

pub struct YajudgeInterceptor {
    private_token: String,
}

pub struct RpcConnection {
    submissions_client: SubmissionManagementClient<InterceptedService<Channel, YajudgeInterceptor>>,
    content_client: CourseContentProviderClient<InterceptedService<Channel, YajudgeInterceptor>>,
    service_properties: ConnectedServiceProperties,
    cancellation_token: CancellationToken,

    logger: Logger,
}

impl RpcConnection {
    pub fn new(
        rpc_config: &RpcConfig,
        logger: Logger,
        jobs_config: &JobsConfig,
        cancellation_token: CancellationToken,
    ) -> RpcConnection {
        let (submissions_client, content_client) = Self::make_client(rpc_config);
        let service_properties =
            Self::make_service_properties(jobs_config.arch_specific_only, jobs_config.name.clone());
        return RpcConnection {
            logger,
            service_properties,
            submissions_client,
            content_client,
            cancellation_token,
        };
    }

    pub fn make_client(
        rpc: &RpcConfig,
    ) -> (
        SubmissionManagementClient<InterceptedService<Channel, YajudgeInterceptor>>,
        CourseContentProviderClient<InterceptedService<Channel, YajudgeInterceptor>>,
    ) {
        let endpoints = &rpc.endpoints;
        let submissions_channel = Self::make_channel(&endpoints.submissions_uri);
        let courses_channel = Self::make_channel(&endpoints.submissions_uri);
        let submissions_interceptor = YajudgeInterceptor {
            private_token: rpc.private_token.clone(),
        };
        let courses_interceptor = YajudgeInterceptor {
            private_token: rpc.private_token.clone(),
        };
        let submissions_client = SubmissionManagementClient::with_interceptor(
            submissions_channel,
            submissions_interceptor,
        );
        let courses_client =
            CourseContentProviderClient::with_interceptor(courses_channel, courses_interceptor);
        return (submissions_client, courses_client);
    }

    pub fn error_can_be_recovered(err: &Box<dyn Error>) -> bool {
        if let Some(&ref status) = err.downcast_ref::<Status>() {
            let code = status.code();
            return match code {
                Code::Internal => true, // nginx timeout shutdown causes to 'h2 protocol error' internal error
                _ => false,
            };
        }

        return false;
    }

    fn make_channel(uri: &Uri) -> Channel {
        let mut scheme = match uri.scheme() {
            Some(s) => s,
            None => "unix",
        };
        if scheme == "grpc" {
            scheme = "http";
        }
        if scheme == "grpcs" {
            scheme = "https"
        }
        let path = uri.path_to_string().expect("Bad URI path");
        let port = match uri.port() {
            Some(value) => value as i32,
            None => match scheme {
                "http" => 80,
                "https" => 443,
                _ => 0,
            },
        };
        let endpoint_string = if scheme == "unix" {
            format!("unix://{}", path)
        } else {
            let host = uri.host_to_string().expect("Bad URI hostname").unwrap();
            format!("{}://{}:{}{}", scheme, host, port, path)
        };
        let endpoint = Endpoint::from_str(endpoint_string.as_str()).expect("Bad endpoint URI");
        let channel = endpoint.connect_lazy();
        return channel;
    }

    fn make_service_properties(
        arch_specific_only: bool,
        name: String,
    ) -> ConnectedServiceProperties {
        ConnectedServiceProperties {
            arch_specific_only_jobs: arch_specific_only,
            number_of_workers: 16,   // TODO use thread pool size
            performance_rating: 1.0, // TODO calculate me
            name,
            role: ServiceRole::ServiceGrading as i32,
            platform: Some(Self::make_grading_platform()),
        }
    }

    fn make_grading_platform() -> GradingPlatform {
        let arch = match std::env::consts::ARCH {
            "x86" => Arch::X86,
            "x86_64" => Arch::X8664,
            "arm" => Arch::Armv7,
            "aarch64" => Arch::Aarch64,
            _ => panic!(
                "Unsupported platform to run grader: {}",
                std::env::consts::ARCH
            ),
        };

        GradingPlatform { arch: arch as i32 }
    }

    pub async fn serve_until_disconnected(
        &mut self,
        storage: &StorageManager,
    ) -> Result<(), Box<dyn Error>> {
        let status = ConnectedServiceStatus {
            properties: Some(self.service_properties.clone()),
            status: ServiceStatus::Idle as i32,
            capacity: 16,
        };
        self.submissions_client
            .set_external_service_status(status)
            .await?;

        let mut stream = self
            .submissions_client
            .receive_submissions_to_process(self.service_properties.clone())
            .await?
            .into_inner();

        loop {
            select! {
                message = stream.message() => {
                    if message.is_err() {
                        return Result::Err(Box::new(message.unwrap_err()));
                    }
                    let submission = message.unwrap().unwrap();
                    debug!(
                        self.logger,
                        "Got submission {} {}", submission.id, submission.problem_id
                    );
                    match self.fetch_submission(submission, storage).await {
                        Err(err) => {
                            error!(self.logger, "Failed to fetch submission: {}", err)
                        },
                        Ok(id) => {
                            self.enque_submission_to_process(id)
                        }
                    }
                }

                _ = self.cancellation_token.cancelled() => {
                    break;
                }
            }
        }

        Ok(())
    }

    pub async fn serve(&mut self, storage: &StorageManager) -> Result<(), Box<dyn Error>> {
        loop {
            let serve_result = self.serve_until_disconnected(storage).await;
            if serve_result.is_ok() {
                return Ok(()); // graceful shutdown from 'serve_until_disconnected'
            }
            if serve_result.is_err() {
                let err = serve_result.unwrap_err();
                if !Self::error_can_be_recovered(&err) {
                    error!(self.logger, "Connection error: {}", err);
                    return Result::Err(err);
                }
                debug!(
                    self.logger,
                    "Got gRPC error that can be recovered after {} secs: {}",
                    RECONNECT_TIMEOUT,
                    err
                );
            }
            let must_stop = select! {
                _ = sleep(Duration::from_secs(RECONNECT_TIMEOUT)) => {
                    false
                }
                _ = self.cancellation_token.cancelled() => {
                    true
                }
            };
            if must_stop {
                return Ok(());
            }
        }
    }

    async fn fetch_submission(
        &mut self,
        submission: Submission,
        storage: &StorageManager,
    ) -> Result<i64, Box<dyn Error>> {
        let soltion_files = &submission.solution_files;
        if soltion_files.clone().unwrap().files.is_empty() {
            return Err(string_error::into_err(format!(
                "Submission {} has no solution files",
                submission.id
            )));
        }
        let course_id = submission.course.clone().unwrap().data_id;
        let problem_id = submission.problem_id.clone();
        let timestamp = storage
            .get_problem_timestamp(&course_id, &problem_id)
            .unwrap_or(0);
        let content_request = ProblemContentRequest {
            course_data_id: course_id,
            problem_id,
            cached_timestamp: timestamp,
        };
        let content_response = self
            .content_client
            .get_problem_full_content(content_request)
            .await?
            .into_inner();
        if content_response.status == ContentStatus::HasData as i32 {
            storage.store_problem(content_response)?;
        }

        storage.store_submission(submission)
    }

    fn enque_submission_to_process(&mut self, id: i64) {}
}

impl Interceptor for YajudgeInterceptor {
    fn call(&mut self, mut request: tonic::Request<()>) -> Result<tonic::Request<()>, Status> {
        let metadata = request.metadata_mut();
        let value = MetadataValue::try_from(&self.private_token).unwrap();
        metadata.insert("token", value);
        Ok(request)
    }
}

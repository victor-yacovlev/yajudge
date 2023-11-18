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

use anyhow::Result;
use slog::Logger;
use std::{str::FromStr, time::Duration};
use tokio::{
    select,
    sync::mpsc::{UnboundedReceiver, UnboundedSender},
    time::sleep,
};
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
    submissions_uri: Uri,
    content_client: CourseContentProviderClient<InterceptedService<Channel, YajudgeInterceptor>>,
    content_uri: Uri,
    service_properties: ConnectedServiceProperties,
    cancellation_token: CancellationToken,

    storage: StorageManager,
    logger: Logger,
}

impl RpcConnection {
    pub fn new(
        rpc_config: &RpcConfig,
        logger: Logger,
        jobs_config: &JobsConfig,
        cancellation_token: CancellationToken,
        storage: StorageManager,
    ) -> RpcConnection {
        let (submissions_client, content_client) = Self::make_client(rpc_config);
        let submissions_uri = rpc_config.endpoints.submissions_uri.clone();
        let content_uri = rpc_config.endpoints.courses_content_uri.clone();
        let service_properties =
            Self::make_service_properties(jobs_config.arch_specific_only, jobs_config.name.clone());
        return RpcConnection {
            logger,
            service_properties,
            submissions_client,
            submissions_uri,
            content_client,
            content_uri,
            cancellation_token,
            storage,
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
        let courses_channel = Self::make_channel(&endpoints.courses_content_uri);
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

    pub async fn serve(
        &mut self,
        status_stream: &mut UnboundedReceiver<usize>,
        finished_stream: &mut UnboundedReceiver<Submission>,
        processor_sink: &mut UnboundedSender<Submission>,
    ) -> Result<()> {
        let mut rpc_stream = self
            .submissions_client
            .receive_submissions_to_process(self.service_properties.clone())
            .await?
            .into_inner();

        loop {
            select! {
                message = rpc_stream.message() => {
                    if message.is_err() {
                        let error_status = message.unwrap_err();
                        let error_code = error_status.code();
                        match error_code {
                            // nginx timeout shutdown causes to 'h2 protocol error' internal error
                            // so this error is recoverable -> just wait and reconnect
                            Code::Internal => {
                                debug!(
                                    self.logger,
                                    "Got gRPC error that can be recovered after {} secs: {}",
                                    RECONNECT_TIMEOUT,
                                    error_status,
                                );
                                _ = sleep(Duration::from_secs(RECONNECT_TIMEOUT));
                                continue;
                            }
                            _ => bail!(
                                    "RPC Stream error while accessing {}: {}",
                                    self.submissions_uri,
                                    error_status,
                                )
                        }
                    }
                    else if let Some(submission) = message.unwrap() {
                        debug!(
                            self.logger,
                            "Got submission {} {}", submission.id, submission.problem_id
                        );
                        match self.fetch_submission_problem(&submission).await {
                            Err(err) => {
                                error!(self.logger, "Failed to fetch submission problem: {}", err)
                            },
                            Ok(()) => {
                                let enqued = Self::enque_submission_to_process(processor_sink, submission);
                                if enqued.is_err() {
                                    error!(self.logger, "Failed to enque submission: {}", enqued.unwrap_err());
                                }
                            }
                        }
                    }
                }

                _ = self.cancellation_token.cancelled() => {
                    debug!(self.logger, "RPC shutting down");
                    break;
                }

                free_workers_or_none = status_stream.recv() => {
                    if let Some(free_workers) = free_workers_or_none {
                        let service_status = if free_workers > 0 { ServiceStatus::Idle } else { ServiceStatus::Busy };
                        let connected_service_status = ConnectedServiceStatus {
                            properties: Some(self.service_properties.clone()),
                            status: service_status as i32,
                            capacity: free_workers as i32,
                        };
                        self.submissions_client
                            .set_external_service_status(connected_service_status)
                            .await?;
                        continue;
                    }
                }

                finished_submission_or_none = finished_stream.recv() => {
                    if let Some(finished_submission) = finished_submission_or_none {
                        let submission_id = &finished_submission.id.clone();
                        let send_status = self.submissions_client.update_grader_output(finished_submission).await;
                        if send_status.is_err() {
                            error!(self.logger, "Can't send submission {} result to server: {}", submission_id, send_status.unwrap_err());
                        }
                        else {
                            debug!(self.logger, "Sent submission {} result to server", submission_id);
                        }
                    }
                }
            }
        }

        Ok(())
    }

    async fn fetch_submission_problem(&mut self, submission: &Submission) -> Result<()> {
        let soltion_files = &submission.solution_files;
        if soltion_files.clone().unwrap().files.is_empty() {
            bail!("Submission {} has no solution files", submission.id);
        }
        let course_id = submission.course.clone().unwrap().data_id;
        let problem_id = submission.problem_id.clone();
        let timestamp = self
            .storage
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
            self.storage.store_problem(content_response)?;
        }

        Ok(())
    }

    fn enque_submission_to_process(
        processor_sink: &mut UnboundedSender<Submission>,
        submission: Submission,
    ) -> Result<()> {
        processor_sink.send(submission)?;

        Ok(())
    }
}

impl Interceptor for YajudgeInterceptor {
    fn call(&mut self, mut request: tonic::Request<()>) -> Result<tonic::Request<()>, Status> {
        let metadata = request.metadata_mut();
        let value = MetadataValue::try_from(&self.private_token).unwrap();
        metadata.insert("token", value);
        Ok(request)
    }
}

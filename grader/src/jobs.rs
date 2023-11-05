use std::collections::BTreeSet;

use crate::{
    generated::yajudge::Submission, processor::SubmissionProcessor, properties::GraderConfig,
    storage::StorageManager,
};
use slog::Logger;
use threadpool::ThreadPool;
use tokio::{
    select,
    sync::mpsc::{self, UnboundedReceiver, UnboundedSender},
};
use tokio_util::sync::CancellationToken;

#[allow(dead_code)]
pub struct JobsManager {
    config: GraderConfig,
    storage: StorageManager,
    thread_pool: ThreadPool,
    cancellation_token: CancellationToken,
    submissions_in_progress: BTreeSet<i64>,
    logger: Logger,
    internal_jobs_sink: UnboundedSender<Submission>,
    internal_jobs_stream: UnboundedReceiver<Submission>,
}

impl JobsManager {
    pub fn new(
        config: GraderConfig,
        storage: StorageManager,
        logger: Logger,
        cancellation_token: CancellationToken,
    ) -> JobsManager {
        let thread_pool = ThreadPool::new(config.jobs.workers);
        let (sink, stream) = mpsc::unbounded_channel::<Submission>();

        JobsManager {
            config,
            storage,
            thread_pool,
            cancellation_token,
            submissions_in_progress: BTreeSet::new(),
            logger,
            internal_jobs_sink: sink,
            internal_jobs_stream: stream,
        }
    }

    pub fn get_free_workers_count(&self) -> usize {
        self.thread_pool.max_count() - self.thread_pool.active_count()
    }

    pub async fn serve(
        &mut self,
        status_sink: UnboundedSender<usize>,
        finished_sink: UnboundedSender<Submission>,
        mut stream: UnboundedReceiver<Submission>,
    ) {
        loop {
            let status = status_sink.send(self.get_free_workers_count());
            if status.is_err() {
                error!(
                    self.logger,
                    "Failed to send jobs manager status: {}",
                    status.unwrap_err()
                );
            }
            select! {

                _ = self.cancellation_token.cancelled() => {
                    debug!(self.logger, "Job manager shutting down");
                    break;
                }

                submission_or_none = stream.recv() => {
                    if let Some(submission) = submission_or_none {
                        let submission_id = &submission.id;
                        if self.submissions_in_progress.contains(submission_id) {
                            error!(self.logger, "Enqued submission that already in progress: {}", submission_id);
                        }
                        else {
                            debug!(self.logger, "Enqued submission {}", submission_id);
                            self.launch_task(submission)
                        }
                    }
                }

                finished_submission_or_none = self.internal_jobs_stream.recv() => {
                    if let Some(submission) = finished_submission_or_none {
                        let submission_id = &submission.id.clone();
                        info!(self.logger, "Submission {} finished", submission_id);
                        let send_status = finished_sink.send(submission);
                        if send_status.is_err() {
                            error!(self.logger, "Can't send finished submission {} to RPC: {}", submission_id, send_status.unwrap_err());
                        }
                        self.submissions_in_progress.remove(submission_id);
                    }
                }

            }
        }
    }

    fn launch_task(&mut self, submission: Submission) {
        let submission_id = submission.id;
        self.submissions_in_progress.insert(submission_id);
        let mut processor = SubmissionProcessor::new(
            self.config.clone(),
            self.logger
                .new(o!("name" => format!("Submission {} processor", &submission.id))),
            self.storage.clone(),
            submission,
        );
        let result_sink = self.internal_jobs_sink.clone();

        self.thread_pool.execute(move || {
            processor.run();
            let result = processor.submission;
            let send_status = result_sink.send(result);
            if send_status.is_err() {
                error!(
                    processor.logger,
                    "Can't send finished submission from processor: {}",
                    send_status.unwrap_err()
                );
            }
        });
    }
}

use std::error::Error;

use slog::Logger;
use string_error::into_err;

use crate::{
    generated::yajudge::{SolutionStatus, Submission},
    properties::GraderConfig,
    storage::StorageManager,
};

#[derive(Clone)]
#[allow(dead_code)]
pub struct SubmissionProcessor {
    pub logger: Logger,
    pub submission: Submission,

    storage: StorageManager,
    config: GraderConfig,
}

impl SubmissionProcessor {
    pub fn new(
        config: GraderConfig,
        logger: Logger,
        storage: StorageManager,
        submission: Submission,
    ) -> SubmissionProcessor {
        SubmissionProcessor {
            logger,
            submission,
            storage,
            config,
        }
    }

    pub fn run(&mut self) {
        let process_status = self.process_submission();
        if process_status.is_err() {
            self.submission.set_status(SolutionStatus::CheckFailed);
            self.submission.build_error_log = process_status.unwrap_err().to_string();
            error!(
                self.logger,
                "Submission procession failed: {}", &self.submission.build_error_log,
            );
        } else {
            info!(
                self.logger,
                "Submission {} done with status {}",
                &self.submission.id,
                &self.submission.status.to_string(),
            );
        }
    }

    fn process_submission(&mut self) -> Result<(), Box<dyn Error>> {
        self.storage.store_submission(&self.submission)?;

        Err(into_err(
            "Not all functionality implemented yet".to_string(),
        ))
        // Ok(())
    }
}

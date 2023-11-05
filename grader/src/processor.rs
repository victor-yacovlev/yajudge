use std::{error::Error, path::Path};

use slog::Logger;
use string_error::into_err;

use crate::{
    builders::BuilderFactory,
    generated::yajudge::{SolutionStatus, Submission},
    properties::GraderConfig,
    storage::StorageManager,
};

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
        let submission_root = self.storage.get_submission_root(self.submission.id);

        Self::process_stored_submission(&self.logger, &self.storage, &submission_root)
    }

    fn process_stored_submission(
        logger: &Logger,
        storage: &StorageManager,
        submission_root: &Path,
    ) -> Result<(), Box<dyn Error>> {
        let submission = storage.get_submission(submission_root);
        let builder_factory =
            BuilderFactory::new(logger.new(o!("part" => "builder_factory")), storage.clone());
        let problem_root = storage.get_problem_root(
            &submission.course.as_ref().unwrap().data_id,
            &submission.problem_id,
        );
        let grading_options = storage.get_problem_grading_options(&problem_root)?;
        let builder = builder_factory.create_builder(&submission, &grading_options)?;
        let _build_relative_path = submission_root.join("build");
        let _code_check_result = builder.check_style(&submission);

        Err(into_err(
            "Not all functionality implemented yet".to_string(),
        ))
        // Ok(())
    }
}

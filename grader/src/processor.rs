use anyhow::Result;
use slog::Logger;
use std::path::Path;

use crate::{
    builders::BuilderFactory,
    generated::yajudge::{SolutionStatus, Submission},
    properties::grader_conf::GraderConfig,
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
        match process_status {
            Err(error) => {
                self.submission.set_status(SolutionStatus::CheckFailed);
                self.submission.build_error_log = error.to_string();
                error!(
                    self.logger,
                    "Submission procession failed: {}", &self.submission.build_error_log,
                );
            }
            Ok(submission) => {
                self.submission = submission;
                let status_code = self.submission.status;
                let status = match SolutionStatus::try_from(status_code) {
                    Ok(known_status) => {
                        format!("{} ({})", status_code, known_status.as_str_name())
                    }
                    Err(_) => format!("{}", status_code),
                };
                info!(
                    self.logger,
                    "Submission {} done with status {}", &self.submission.id, status,
                );
            }
        }
    }

    fn process_submission(&mut self) -> Result<Submission> {
        self.storage.store_submission(&self.submission)?;
        let submission_root = self.storage.get_submission_root(self.submission.id);

        Self::process_stored_submission(&self.logger, &self.storage, &submission_root)
    }

    fn process_stored_submission(
        logger: &Logger,
        storage: &StorageManager,
        submission_root: &Path,
    ) -> Result<Submission> {
        let mut submission = storage.get_submission(submission_root);
        let builder_factory =
            BuilderFactory::new(logger.new(o!("part" => "builder_factory")), storage.clone());
        let problem_root = storage.get_problem_root(
            &submission.course.as_ref().unwrap().data_id,
            &submission.problem_id,
        );
        let grading_options = storage.get_problem_grading_options(&problem_root)?;
        let builder = builder_factory.create_builder(&submission, &grading_options)?;
        let _build_relative_path = submission_root.join("build");
        let style_check_errors = builder.check_style(&submission)?;
        if style_check_errors.len() > 0 {
            submission.status = SolutionStatus::StyleCheckError.into();
            let error_message = style_check_errors
                .iter()
                .fold(String::new(), |a, b| a + "\n\n" + &b.to_string());
            submission.style_error_log = error_message.trim().into();

            return Ok(submission);
        }

        Err(anyhow!("Not all functionality implemented yet"))
        // Ok(())
    }
}

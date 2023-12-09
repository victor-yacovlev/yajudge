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

        self.process_stored_submission(&submission_root)
    }

    fn process_stored_submission(&self, submission_root: &Path) -> Result<Submission> {
        let mut submission = self.storage.get_submission(submission_root);
        let builder_logger = self.logger.new(o!("part" => "builder_factory"));
        let default_build_properties = &self.config.default_build_properties;
        let builder_factory =
            BuilderFactory::new(builder_logger, &self.storage, default_build_properties);
        let problem_root = self.storage.get_problem_root(
            &submission.course.as_ref().unwrap().data_id,
            &submission.problem_id,
        );
        let grading_options = self.storage.get_problem_grading_options(&problem_root)?;
        let builder = builder_factory.create_builder(&submission, &grading_options)?;
        let style_check_log_path = submission_root.join("build/stylecheck.log");
        let build_log_path = submission_root.join("build/build.log");

        let style_check_result = builder.check_style(&submission);
        if let Err(style_check_error) = style_check_result {
            match style_check_error {
                crate::builders::BuilderError::SystemError(error) => {
                    let message = &error.to_string();
                    let message_bytes = message.as_bytes();
                    let _ =
                        StorageManager::store_binary(&style_check_log_path, message_bytes, false);
                    return Err(error);
                }
                crate::builders::BuilderError::UserError(user_errors) => {
                    submission.status = SolutionStatus::StyleCheckError.into();
                    let error_message = user_errors
                        .iter()
                        .fold(String::new(), |a, b| a + "\n\n" + &b.to_string());
                    submission.style_error_log = error_message.trim().into();
                    let message_bytes = error_message.as_bytes();
                    let _ =
                        StorageManager::store_binary(&style_check_log_path, message_bytes, false);

                    return Ok(submission);
                }
            }
        }

        let build_result = builder.build(&submission);
        if let Err(build_error) = build_result {
            match build_error {
                crate::builders::BuilderError::SystemError(error) => {
                    let message = &error.to_string();
                    let message_bytes = message.as_bytes();
                    let _ = StorageManager::store_binary(&build_log_path, message_bytes, false);
                    return Err(error);
                }
                crate::builders::BuilderError::UserError(user_errors) => {
                    submission.status = SolutionStatus::CompilationError.into();
                    let error_message = user_errors
                        .iter()
                        .fold(String::new(), |a, b| a + "\n\n" + &b.to_string());
                    submission.build_error_log = error_message.trim().into();
                    let message_bytes = error_message.as_bytes();
                    let _ = StorageManager::store_binary(&build_log_path, message_bytes, false);

                    return Ok(submission);
                }
            }
        }

        Ok(submission)
    }
}

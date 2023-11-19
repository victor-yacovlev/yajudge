use anyhow::Result;
use std::path::{Path, PathBuf};

use slog::Logger;

use crate::{
    generated::yajudge::{ExecutableTarget, FileSet, Submission},
    runner::Runner,
    storage::StorageManager,
};

use super::{BuildResult, Builder, BuilderDetection, StyleCheckError, StyleCheckResult};

pub struct CLangToolchain {
    logger: Logger,
    storage: StorageManager,
}

impl CLangToolchain {
    pub fn new(logger: Logger, storage: StorageManager) -> CLangToolchain {
        CLangToolchain {
            logger,
            storage: storage.clone(),
        }
    }
}

impl Builder for CLangToolchain {
    fn build(
        &self,
        _submission: &Submission,
        _build_relative_path: &Path,
        _target: &ExecutableTarget,
    ) -> BuildResult {
        todo!()
    }

    fn check_style(&self, submission: &Submission) -> Result<StyleCheckResult> {
        let course_id = &submission.course.as_ref().unwrap().data_id;
        let problem_id = &submission.problem_id;
        let problem_root = self.storage.get_problem_root(course_id, problem_id);
        let grading_options = self
            .storage
            .get_problem_grading_options(&problem_root)
            .expect("No grading options stored");
        let submission_root = self.storage.get_submission_root(submission.id);
        let system_root = self.storage.get_system_root();
        let runner_logger = self.logger.new(o!("part" => "check_style_runner"));
        let mut runner = Runner::new(
            runner_logger,
            None,
            &system_root,
            &problem_root,
            &submission_root,
        );
        runner.set_relative_workdir(&PathBuf::from("/build"));
        let mut errors = Vec::<StyleCheckError>::new();
        for source in &submission.solution_files.as_ref().unwrap().files {
            let file_name = &source.name;
            let source_path = PathBuf::from(&file_name);
            let suffix = source_path
                .as_path()
                .extension()
                .unwrap_or_default()
                .to_str()
                .unwrap();
            let mut can_check = false;
            for style in &grading_options.code_styles {
                let style_suffix_pattern = &style.source_file_suffix;
                if style_suffix_pattern.eq_ignore_ascii_case(&suffix) {
                    can_check = true;
                    break;
                }
            }
            if !can_check {
                continue;
            }
            let clang_format =
                runner.run_command("clang-format", vec!["-style=file", file_name.as_str()])?;
            if !clang_format.exit_status.is_success() {
                return Err(anyhow!(
                    "clang-format failed: {}",
                    clang_format.exit_status.to_string()
                ));
            }
            let formatted_bytes = clang_format.stdout;
            let formatted_file_name = format!("{}.formatted", &file_name);
            let formatted_file_path = submission_root
                .join("upperdir")
                .join("build")
                .join(&formatted_file_name);
            StorageManager::store_binary(&formatted_file_path, &formatted_bytes, false)?;
            let diff = runner.run_command(
                "diff",
                vec![file_name.as_str(), formatted_file_name.as_str()],
            )?;
            if !diff.exit_status.is_success() {
                let stdout_string = String::from_utf8(diff.stdout)
                    .unwrap_or("Can't convert utf-8 output from diff stdout".into());
                let stderr_string = String::from_utf8(diff.stderr)
                    .unwrap_or("Can't convert utf-8 output from diff stderr".into());
                let message = stdout_string + "\n" + &stderr_string;
                let style_check_error = StyleCheckError {
                    file_name: file_name.clone(),
                    message,
                };
                errors.insert(errors.len(), style_check_error);
                continue;
            }
            runner.reset();
        }

        Ok(errors)
    }
}

impl BuilderDetection for CLangToolchain {
    fn can_build(submission: &Submission) -> bool {
        let file_set = submission.solution_files.as_ref().unwrap();
        has_file_by_pattern(file_set, ".c")
            || has_file_by_pattern(file_set, ".cpp")
            || has_file_by_pattern(file_set, ".cc")
            || has_file_by_pattern(file_set, ".cxx")
            || has_file_by_pattern(file_set, ".S")
            || has_file_by_pattern(file_set, ".s")
    }
}

fn has_file_by_pattern(file_set: &FileSet, pattern: &str) -> bool {
    let files = file_set.files.as_slice();
    for file in files {
        if file.name.ends_with(pattern) {
            return true;
        }
    }

    false
}

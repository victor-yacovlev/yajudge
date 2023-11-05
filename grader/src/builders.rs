use anyhow::{bail, Result};
#[allow(unused_imports)]
use std::path::Path;
use std::path::PathBuf;

use slog::Logger;


use crate::{
    generated::yajudge::{BuildSystem, ExecutableTarget, FileSet, GradingOptions, Submission},
    runner::{IsolatedRunner, Runner},
    storage::StorageManager,
};

pub struct BuildArtifact {
    pub executable_target: ExecutableTarget,
    pub file_names: Vec<String>,
}

pub type BuildResult = Result<Vec<BuildArtifact>, String>;

pub struct StyleCheckError {
    pub file_name: String,
    pub message: String,
}

pub type StyleCheckResult = Result<(), Vec<StyleCheckError>>;

pub trait Builder {
    fn build(
        &self,
        submission: &Submission,
        build_relative_path: &Path,
        target: &ExecutableTarget,
    ) -> BuildResult;

    fn check_style(&self, submission: &Submission) -> StyleCheckResult;
}

trait BuilderDetection {
    fn can_build(submission: &Submission) -> bool;
}

pub struct BuilderFactory {
    logger: Logger,
    storage: StorageManager,
}

impl BuilderFactory {
    pub fn new(logger: Logger, storage: StorageManager) -> BuilderFactory {
        BuilderFactory { logger, storage }
    }

    pub fn create_builder(
        &self,
        submission: &Submission,
        options: &GradingOptions,
    ) -> Result<Box<dyn Builder>> {
        let build_system = BuildSystem::from_i32(options.build_system);
        if build_system.is_none() {
            bail!("Wrong build system enum value {}", options.build_system);
        }
        match build_system.unwrap() {
            BuildSystem::AutodetectBuild => self.detect_builder(submission),
            BuildSystem::ClangToolchain => Ok(Box::new(CLangToolchain::new(
                self.logger.new(o!("name" => "clang_toolchain")),
                self.storage.clone(),
            ))),
            BuildSystem::SkipBuild => Ok(Box::new(VoidToolchain::new(
                self.logger.new(o!("name" => "void_toolchain")),
            ))),
            _ => bail!(
                "Build system {} not implemented yet",
                build_system.unwrap().as_str_name()
            ),
        }
    }

    fn detect_builder(&self, submission: &Submission) -> Result<Box<dyn Builder>> {
        if CLangToolchain::can_build(submission) {
            return Ok(Box::new(CLangToolchain::new(
                self.logger
                    .new(o!("name" => "clang_toolchain_autodetected")),
                self.storage.clone(),
            )));
        }
        if VoidToolchain::can_build(submission) {
            return Ok(Box::new(VoidToolchain::new(
                self.logger.new(o!("name" => "void_toolchain_autodetected")),
            )));
        }
        bail!("Can't detect build system by provided solition files set")
    }
}

pub struct VoidToolchain {
    logger: Logger,
}
pub struct CLangToolchain {
    logger: Logger,
    storage: StorageManager,
}

impl VoidToolchain {
    pub fn new(logger: Logger) -> VoidToolchain {
        VoidToolchain { logger }
    }
}

impl Builder for VoidToolchain {
    fn build(
        &self,
        _submission: &Submission,
        _build_relative_path: &Path,
        _target: &ExecutableTarget,
    ) -> BuildResult {
        todo!()
    }

    fn check_style(&self, _submission: &Submission) -> StyleCheckResult {
        Ok(())
    }
}

impl BuilderDetection for VoidToolchain {
    fn can_build(_submission: &Submission) -> bool {
        true
    }
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

    fn check_style(&self, submission: &Submission) -> StyleCheckResult {
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
        let mut runner = IsolatedRunner::new(
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
            let clang_format = String::from("clang-format");
            let args = vec![String::from("-style=file"), file_name.clone()];
            let start_result = runner.start(&clang_format, &args);
            if start_result.is_err() {
                let err = start_result.err().unwrap();
                let style_check_error = StyleCheckError {
                    file_name: file_name.clone(),
                    message: err.to_string(),
                };
                errors.insert(errors.len(), style_check_error);
                continue;
            }
            runner
                .process_envents_until_finished()
                .expect("Can't wait for clang-format process finished");
            if runner.get_exit_status() != 0 {
                let stderr = runner.read_stderr();
                let style_check_error = StyleCheckError {
                    file_name: file_name.clone(),
                    message: String::from_utf8(stderr)
                        .expect("Can't convert utf-8 output from clang-format"),
                };
                errors.insert(errors.len(), style_check_error);
                continue;
            }
        }

        if errors.is_empty() {
            Ok(())
        } else {
            Err(errors)
        }
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

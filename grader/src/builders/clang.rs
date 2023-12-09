use anyhow::Result;
use std::{collections::HashSet, path::PathBuf};

use slog::Logger;

use crate::{
    generated::yajudge::{ExecutableTarget, Submission},
    properties::{
        build_props::{string_to_set, BuildProperties, LanguageBuildProperties},
        UpdatedWith,
    },
    runner::Runner,
    storage::StorageManager,
};

use super::{
    has_file_by_pattern, BuildArtifact, Builder, BuilderDetection, BuilderError, SourceProcessError,
};

pub struct CLangToolchain {
    logger: Logger,
    storage: StorageManager,
    default_build_properties: BuildProperties,
}

impl CLangToolchain {
    pub fn new(
        logger: Logger,
        storage: StorageManager,
        default_build_properties: BuildProperties,
    ) -> CLangToolchain {
        CLangToolchain {
            logger,
            storage,
            default_build_properties,
        }
    }
}

impl Builder for CLangToolchain {
    fn build(&self, submission: &Submission) -> Result<Vec<BuildArtifact>, BuilderError> {
        let course_id = &submission.course.as_ref().unwrap().data_id;
        let problem_id = &submission.problem_id;
        let problem_root = self.storage.get_problem_root(course_id, problem_id);
        let grading_options = self
            .storage
            .get_problem_grading_options(&problem_root)
            .expect("No grading options stored");
        let common_build_props = self.get_build_properties(submission);
        let extra_build_props = &grading_options.build_properties;
        let build_props = common_build_props.updated_with(&extra_build_props);
        let link_options = match build_props.get("link_options") {
            Some(line) => string_to_set(&line),
            None => HashSet::new(),
        };

        let target = &grading_options.executable_target();

        let no_std_lib = link_options.contains("-nostdlib");
        let sanitizer_options = Self::get_sanitizer_options(&build_props, target);
        let enable_sanitizer_target = !sanitizer_options.is_empty() && !no_std_lib;
        let has_native_target = *target == ExecutableTarget::Native
            || *target == ExecutableTarget::NativeWithValgrind
            || *target == ExecutableTarget::NativeWithSanitizersAndValgrind;
        let enable_plain_target = has_native_target || !enable_sanitizer_target;

        let mut artifacts = Vec::<BuildArtifact>::with_capacity(2);

        if enable_plain_target {
            match self.build_target(
                submission,
                &build_props,
                ExecutableTarget::Native,
                HashSet::new(),
            ) {
                Ok(artifact) => artifacts.push(artifact),
                Err(error) => return Err(error),
            }
        }

        if enable_sanitizer_target {
            match self.build_target(
                submission,
                &build_props,
                ExecutableTarget::NativeWithSanitizers,
                sanitizer_options,
            ) {
                Ok(artifact) => artifacts.push(artifact),
                Err(error) => return Err(error),
            }
        }

        Ok(artifacts)
    }

    fn check_style(&self, submission: &Submission) -> Result<(), BuilderError> {
        let course_id = &submission.course.as_ref().unwrap().data_id;
        let problem_id = &submission.problem_id;
        let problem_root = self.storage.get_problem_root(course_id, problem_id);
        let grading_options = self
            .storage
            .get_problem_grading_options(&problem_root)
            .expect("No grading options stored");
        let submission_root = self.storage.get_submission_root(submission.id);
        let mut runner = self.create_runner(submission, "check_style_runner");
        runner.set_relative_workdir(&PathBuf::from("/build"));
        let mut user_errors = Vec::<SourceProcessError>::new();
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
            let clang_format_result =
                runner.run_command("clang-format", vec!["-style=file", file_name.as_str()]);
            if let Err(error) = clang_format_result {
                return Err(BuilderError::SystemError(error));
            }
            let clang_format = clang_format_result.expect("Error already processed");
            if !clang_format.exit_status.is_success() {
                return Err(BuilderError::SystemError(anyhow!(
                    "clang-format failed: {}",
                    clang_format.exit_status.to_string()
                )));
            }
            let formatted_bytes = clang_format.stdout;
            let formatted_file_name = format!("{}.formatted", &file_name);
            let formatted_file_path = submission_root
                .join("upperdir")
                .join("build")
                .join(&formatted_file_name);
            if let Err(error) =
                StorageManager::store_binary(&formatted_file_path, &formatted_bytes, false)
            {
                return Err(BuilderError::SystemError(error));
            }
            let diff_result = runner.run_command(
                "diff",
                vec![file_name.as_str(), formatted_file_name.as_str()],
            );
            if let Err(error) = diff_result {
                return Err(BuilderError::SystemError(error));
            }
            let diff = diff_result.expect("Error already processed");
            if !diff.exit_status.is_success() {
                let stdout_string = String::from_utf8(diff.stdout)
                    .unwrap_or("Can't convert utf-8 output from diff stdout".into());
                let stderr_string = String::from_utf8(diff.stderr)
                    .unwrap_or("Can't convert utf-8 output from diff stderr".into());
                let message = stdout_string + "\n" + &stderr_string;
                let style_check_error = SourceProcessError {
                    file_name: file_name.clone(),
                    message,
                };
                user_errors.insert(user_errors.len(), style_check_error);
                continue;
            }
            runner.reset();
        }

        if user_errors.len() == 0 {
            Result::<(), BuilderError>::Ok(())
        } else {
            Err(BuilderError::UserError(user_errors))
        }
    }
}

impl BuilderDetection for CLangToolchain {
    fn can_build(submission: &Submission) -> bool {
        Self::has_c(submission) || Self::has_cxx(submission) || Self::has_gnu_asm(submission)
    }
}

impl CLangToolchain {
    fn has_c(submission: &Submission) -> bool {
        let file_set = submission.solution_files.as_ref().unwrap();
        has_file_by_pattern(file_set, ".c")
    }
    fn has_cxx(submission: &Submission) -> bool {
        let file_set = submission.solution_files.as_ref().unwrap();
        has_file_by_pattern(file_set, ".cpp")
            || has_file_by_pattern(file_set, ".cxx")
            || has_file_by_pattern(file_set, ".cc")
    }
    fn has_gnu_asm(submission: &Submission) -> bool {
        let file_set = submission.solution_files.as_ref().unwrap();
        has_file_by_pattern(file_set, ".S") || has_file_by_pattern(file_set, ".s")
    }

    fn get_build_properties(&self, submission: &Submission) -> &LanguageBuildProperties {
        if Self::has_cxx(submission) {
            return &self.default_build_properties.cxx;
        } else if Self::has_gnu_asm(submission) {
            return &self.default_build_properties.s;
        } else if Self::has_c(submission) {
            return &self.default_build_properties.c;
        }

        panic!("Unsupported build toolchain")
    }

    fn get_sanitizer_options(
        props: &LanguageBuildProperties,
        target: &ExecutableTarget,
    ) -> HashSet<String> {
        let allow = *target == ExecutableTarget::NativeWithSanitizers
            || *target == ExecutableTarget::NativeWithSanitizersAndValgrind;
        if !allow {
            return HashSet::new();
        }
        if !props.contains_key("sanitizers") {
            return HashSet::new();
        }
        let sanitizers_value = props.get("sanitizers").expect("Value existence checked");
        let sanitizers_set = string_to_set(sanitizers_value);

        let mut result =
            HashSet::from_iter(sanitizers_set.iter().map(|x| format!("-fsanitize={}", x)));
        result.insert("-fno-sanitize-recover=all".into());

        return result;
    }

    fn build_target(
        &self,
        submission: &Submission,
        build_props: &LanguageBuildProperties,
        target: ExecutableTarget,
        sanitizer_options: HashSet<String>,
    ) -> Result<BuildArtifact, BuilderError> {
        let object_suffix = if target == ExecutableTarget::NativeWithSanitizers {
            ".san.o"
        } else {
            ".o"
        };

        let compiler_opt = build_props.get("compiler");
        if compiler_opt == None {
            return Err(BuilderError::SystemError(anyhow!(
                "Compiler not set in configuration"
            )));
        }
        let compiler = compiler_opt.expect("Checked for not-None value");

        let mut compile_options = HashSet::<String>::new();
        if let Some(line) = build_props.get("compile_options") {
            compile_options = string_to_set(line);
        }
        compile_options.extend(sanitizer_options);

        let source_files = &submission
            .solution_files
            .as_ref()
            .expect("Must have solution files")
            .files;

        let mut object_files = Vec::<String>::with_capacity(source_files.len());
        let mut compile_errors = Vec::<SourceProcessError>::with_capacity(source_files.len());

        for source_file in source_files {
            if Self::is_compilable(&source_file.name) {
                let out_name = source_file.name.clone() + object_suffix;
                let compile_result = self.compile_file(
                    compiler,
                    submission,
                    &source_file.name,
                    &out_name,
                    &compile_options,
                );
                if let Err(builder_error) = compile_result {
                    match builder_error {
                        BuilderError::SystemError(error) => {
                            return Err(BuilderError::SystemError(error))
                        }
                        BuilderError::UserError(mut compile_error) => {
                            compile_errors.append(&mut compile_error);
                        }
                    }
                } else {
                    object_files.push(out_name);
                }
            }
        }

        if compile_errors.len() > 0 {
            return Err(BuilderError::UserError(compile_errors));
        }

        let mut link_options = HashSet::<String>::new();
        if let Some(line) = build_props.get("link_options") {
            link_options = string_to_set(line);
        }
        let artifact_name = if target == ExecutableTarget::Native {
            "solution".to_string()
        } else {
            "solution-san".to_string()
        };
        let link_result = self.link_executable(
            compiler,
            submission,
            &object_files,
            &artifact_name,
            &link_options,
        );
        if let Err(error) = link_result {
            return Err(error);
        };

        let artifact = BuildArtifact {
            executable_target: target,
            file_names: vec![artifact_name],
        };

        Ok(artifact)
    }

    fn is_compilable(file_name: &String) -> bool {
        let file_path = PathBuf::from(file_name);
        let suffix = file_path
            .extension()
            .unwrap_or_default()
            .to_str()
            .unwrap_or_default();
        return suffix == "c"
            || suffix == "s"
            || suffix == "S"
            || suffix == "cxx"
            || suffix == "cpp"
            || suffix == "cc";
    }

    fn create_runner(&self, submission: &Submission, log_name: &'static str) -> Runner {
        let course_id = &submission.course.as_ref().unwrap().data_id;
        let problem_id = &submission.problem_id;
        let problem_root = self.storage.get_problem_root(course_id, problem_id);
        let submission_root = self.storage.get_submission_root(submission.id);
        let system_root = self.storage.get_system_root();
        let runner_logger = self.logger.new(o!("part" => log_name));

        Runner::new(
            runner_logger,
            None,
            &system_root,
            &problem_root,
            &submission_root,
        )
    }

    fn compile_file(
        &self,
        compiler: &String,
        submission: &Submission,
        source_name: &String,
        out_name: &String,
        options: &HashSet<String>,
    ) -> Result<(), BuilderError> {
        let mut runner = self.create_runner(submission, "compile_runner");
        runner.set_relative_workdir(&PathBuf::from("/build"));
        let mut args = Vec::<&str>::with_capacity(options.len() + 4);
        for item in options {
            args.push(item.as_str());
        }
        args.push("-c");
        args.push("-o");
        args.push(&out_name.as_str());
        args.push(&source_name.as_str());

        let compile_result = runner.run_command(compiler.as_str(), args);
        if let Err(error) = compile_result {
            return Err(BuilderError::SystemError(error));
        }
        let result = compile_result.expect("Error already processed");
        if !result.exit_status.is_success() {
            let stderr = result.stderr;
            let error_message = String::from_utf8(stderr)
                .unwrap_or(format!("{} returned non-UTF-8 error output", compiler));
            let error_to_report = SourceProcessError {
                file_name: source_name.clone(),
                message: error_message,
            };
            return Err(BuilderError::UserError(vec![error_to_report]));
        }

        Ok(())
    }

    fn link_executable(
        &self,
        linker: &String,
        submission: &Submission,
        object_files: &Vec<String>,
        out_name: &String,
        options: &HashSet<String>,
    ) -> Result<(), BuilderError> {
        let mut runner = self.create_runner(submission, "compile_runner");
        runner.set_relative_workdir(&PathBuf::from("/build"));
        let mut args = Vec::<&str>::with_capacity(options.len() + 2 + object_files.len());
        for item in options {
            args.push(item.as_str());
        }
        args.push("-o");
        args.push(&out_name.as_str());
        for item in object_files {
            args.push(item.as_str());
        }

        let link_result = runner.run_command(linker.as_str(), args);
        if let Err(error) = link_result {
            return Err(BuilderError::SystemError(error));
        }
        let result = link_result.expect("Error already processed");
        if !result.exit_status.is_success() {
            let stderr = result.stderr;
            let error_message = String::from_utf8(stderr)
                .unwrap_or(format!("{} returned non-UTF-8 error output", linker));
            let error_to_report = SourceProcessError {
                file_name: out_name.clone(),
                message: error_message,
            };
            return Err(BuilderError::UserError(vec![error_to_report]));
        }

        Ok(())
    }
}

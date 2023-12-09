mod clang;
mod void;

use anyhow::Result;
use slog::Logger;

use self::clang::CLangToolchain;
use self::void::VoidToolchain;

use crate::{
    generated::yajudge::{BuildSystem, ExecutableTarget, FileSet, GradingOptions, Submission},
    properties::build_props::BuildProperties,
    storage::StorageManager,
};

pub struct BuildArtifact {
    pub executable_target: ExecutableTarget,
    pub file_names: Vec<String>,
}

#[derive(Debug)]
pub struct SourceProcessError {
    pub file_name: String,
    pub message: String,
}

impl ToString for SourceProcessError {
    fn to_string(&self) -> String {
        self.file_name.clone() + &String::from("\n") + &self.message
    }
}

#[derive(Debug)]
pub enum BuilderError {
    SystemError(anyhow::Error),
    UserError(Vec<SourceProcessError>),
}

pub trait Builder {
    fn build(&self, submission: &Submission) -> Result<Vec<BuildArtifact>, BuilderError>;
    fn check_style(&self, submission: &Submission) -> Result<(), BuilderError>;
}

trait BuilderDetection {
    fn can_build(submission: &Submission) -> bool;
}

pub struct BuilderFactory {
    logger: Logger,
    storage: StorageManager,
    default_build_properties: BuildProperties,
}

impl BuilderFactory {
    pub fn new(
        logger: Logger,
        storage: &StorageManager,
        default_build_properties: &BuildProperties,
    ) -> BuilderFactory {
        BuilderFactory {
            logger,
            storage: storage.clone(),
            default_build_properties: default_build_properties.clone(),
        }
    }

    pub fn create_builder(
        &self,
        submission: &Submission,
        options: &GradingOptions,
    ) -> Result<Box<dyn Builder>> {
        let build_system = BuildSystem::try_from(options.build_system);
        if build_system.is_err() {
            bail!("Wrong build system enum value {}", options.build_system);
        }
        match build_system.clone().unwrap() {
            BuildSystem::AutodetectBuild => self.detect_builder(submission),
            BuildSystem::ClangToolchain => Ok(Box::new(CLangToolchain::new(
                self.logger.new(o!("name" => "clang_toolchain")),
                self.storage.clone(),
                self.default_build_properties.clone(),
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
                self.default_build_properties.clone(),
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

pub fn has_file_by_pattern(file_set: &FileSet, pattern: &str) -> bool {
    let files = file_set.files.as_slice();
    for file in files {
        if file.name.ends_with(pattern) {
            return true;
        }
    }

    false
}

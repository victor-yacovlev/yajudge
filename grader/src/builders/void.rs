use anyhow::Result;

use std::path::Path;

use slog::Logger;

use crate::generated::yajudge::{ExecutableTarget, Submission};

use super::{BuildResult, Builder, BuilderDetection, StyleCheckResult};

pub struct VoidToolchain {
    _logger: Logger,
}
impl VoidToolchain {
    pub fn new(logger: Logger) -> VoidToolchain {
        VoidToolchain { _logger: logger }
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

    fn check_style(&self, _submission: &Submission) -> Result<StyleCheckResult> {
        Ok(vec![])
    }
}

impl BuilderDetection for VoidToolchain {
    fn can_build(_submission: &Submission) -> bool {
        true
    }
}

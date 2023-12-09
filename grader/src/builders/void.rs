use anyhow::Result;

use slog::Logger;

use crate::generated::yajudge::Submission;

use super::{BuildArtifact, Builder, BuilderDetection, BuilderError};

pub struct VoidToolchain {
    _logger: Logger,
}
impl VoidToolchain {
    pub fn new(logger: Logger) -> VoidToolchain {
        VoidToolchain { _logger: logger }
    }
}

impl Builder for VoidToolchain {
    fn build(&self, _submission: &Submission) -> Result<Vec<BuildArtifact>, BuilderError> {
        Ok(vec![])
    }

    fn check_style(&self, _submission: &Submission) -> Result<(), BuilderError> {
        Ok(())
    }
}

impl BuilderDetection for VoidToolchain {
    fn can_build(_submission: &Submission) -> bool {
        true
    }
}

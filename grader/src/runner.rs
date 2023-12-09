mod process_monitor;
mod runner_impl;

use anyhow::Result;
use std::path::PathBuf;
use tokio::sync::mpsc::{UnboundedReceiver, UnboundedSender};

use slog::Logger;

use crate::generated::yajudge::GradingLimits;

use self::process_monitor::ProcessMonitor;

#[derive(Clone)]
pub enum ExitResult {
    Finished(u8),
    Killed(u8),
    Timeout,
    StdoutLimit,
    StderrLimit,
}

impl ExitResult {
    pub fn is_success(&self) -> bool {
        match self {
            ExitResult::Finished(status) => 0 == *status,
            ExitResult::Killed(_) => false,
            ExitResult::Timeout => false,
            ExitResult::StdoutLimit => false,
            ExitResult::StderrLimit => false,
        }
    }
}

impl ToString for ExitResult {
    fn to_string(&self) -> String {
        match self {
            ExitResult::Finished(status) => format!("Exited with code {}", status),
            ExitResult::Killed(signum) => format!("Killed by signal {}", signum),
            ExitResult::Timeout => format!("Killed by timeout"),
            ExitResult::StdoutLimit => format!("Reached stdout limit"),
            ExitResult::StderrLimit => format!("Reached stderr limit"),
        }
    }
}

#[derive(Clone)]
pub struct CommandOutput {
    pub exit_status: ExitResult,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
}

impl CommandOutput {
    pub fn is_success(&self) -> bool {
        match self.exit_status {
            ExitResult::Finished(status) => 0 == status,
            _ => false,
        }
    }

    pub fn stdout_as_string(&self) -> String {
        String::from_utf8(self.stdout.clone()).expect("Can't convert command stdout to utf-8")
    }

    pub fn stderr_as_string(&self) -> String {
        String::from_utf8(self.stderr.clone()).expect("Can't convert command stderr to utf-8")
    }

    pub fn get_error_message(maybe_output: &Result<CommandOutput>) -> Option<String> {
        match maybe_output {
            Err(e) => Some(e.to_string()),
            Ok(r) => {
                if r.is_success() {
                    None
                } else {
                    let stderr = r.stderr_as_string();
                    let message = if !stderr.is_empty() {
                        stderr
                    } else {
                        r.exit_status.to_string()
                    };
                    Some(message)
                }
            }
        }
    }
}

struct LaunchCmd {
    program: String,
    arguments: Vec<String>,
}

impl ToString for LaunchCmd {
    fn to_string(&self) -> String {
        let mut result = self.program.clone();
        for arg in &self.arguments {
            result += " ";
            result += arg;
        }
        return result;
    }
}

pub struct Runner {
    logger: Logger,
    limits: Option<GradingLimits>,
    system_root: PathBuf,
    problem_root: PathBuf,
    submission_root: PathBuf,

    relative_workdir: PathBuf,
    exit_result: Option<ExitResult>,

    child: Option<ProcessMonitor>,

    stdout_sender: Option<UnboundedSender<Vec<u8>>>,
    stdout_receiver: Option<UnboundedReceiver<Vec<u8>>>,
    stderr_sender: Option<UnboundedSender<Vec<u8>>>,
    stderr_receiver: Option<UnboundedReceiver<Vec<u8>>>,
}

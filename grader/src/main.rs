pub mod builders;
pub mod grader;
pub mod jobs;
pub mod processor;
pub mod properties;
pub mod rpc;
pub mod runner;
pub mod storage;
pub mod generated {
    pub mod yajudge;
}

#[macro_use]
extern crate slog;
#[macro_use]
extern crate anyhow;

use anyhow::Result;
use clap::{Arg, Command};
use grader::Grader;

use crate::properties::GraderConfig;

#[tokio::main]
async fn main() -> Result<()> {
    let arg_matches = Command::new("Yajudge Grader")
        .about("Starts Yajudge grader service")
        .arg_required_else_help(true)
        .arg(Arg::new("config").long("config").short('C').required(true))
        .arg(
            Arg::new("name")
                .long("name")
                .short('N')
                .required(false)
                .default_value("default"),
        )
        .arg(
            Arg::new("log-path")
                .long("log-path")
                .short('L')
                .required(false),
        )
        .arg(
            Arg::new("log-level")
                .long("log-level")
                .short('l')
                .required(false),
        )
        .get_matches();
    let config = GraderConfig::from_args(arg_matches);
    let mut grader = Grader::new(config)?;

    grader.main().await
}

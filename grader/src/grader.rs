#[allow(unused_imports)]
use crate::properties::JobsConfig;
use crate::properties::{GraderConfig, LogConfig};
use slog::{Drain, Level, Logger};
use slog_term;
use std::io::Write;
use std::{self};
use tokio::runtime::Runtime;
pub struct Grader {
    config: GraderConfig,
    log: Logger,
    runtime: Runtime,
}

impl Grader {
    pub fn new(config: GraderConfig) -> Grader {
        let log = Self::setup_logger(&config.log);
        // max tasks = workers + gRPC fetcher + gRPC pusher + signal handler
        let max_tasks = &config.jobs.workers + 3;
        let runtime = Self::setup_runtime(max_tasks);
        let grader = Grader {
            config,
            log,
            runtime,
        };
        info!(grader.log, "Grader initialized");
        return grader;
    }

    fn setup_logger(config: &LogConfig) -> Logger {
        let path = &config.path;
        let path_str = path.to_str().unwrap();
        return match path_str {
            "" | "stdout" => Self::create_logger_from_sink(std::io::stdout(), config.level),
            "stderr" => Self::create_logger_from_sink(std::io::stderr(), config.level),
            _ => {
                let file_open_result = std::fs::OpenOptions::new()
                    .create(true)
                    .append(true)
                    .write(true)
                    .open(path);
                if file_open_result.is_err() {
                    let path_str = path.to_str().unwrap();
                    let error = file_open_result.unwrap_err();
                    panic!("Can't open log file {path_str}: {error}");
                }
                let file = file_open_result.unwrap();
                Self::create_logger_from_sink(file, config.level)
            }
        };
    }

    fn create_logger_from_sink<T: Write + std::marker::Send + 'static>(
        sink: T,
        level: Level,
    ) -> Logger {
        let decorator = slog_term::PlainDecorator::new(sink);
        let drain = slog_term::FullFormat::new(decorator).build().fuse();
        let drain = slog_async::Async::new(drain).build().fuse();
        let drain = slog::LevelFilter::new(drain, level).fuse();
        return slog::Logger::root(drain, o!());
    }

    fn setup_runtime(max_tasks: usize) -> Runtime {
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(max_tasks)
            .build()
            .unwrap();
        return runtime;
    }

    pub fn main(self) {}
}

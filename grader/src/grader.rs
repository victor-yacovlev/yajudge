use crate::generated::yajudge::Submission;
use crate::jobs::JobsManager;
use crate::properties::{GraderConfig, JobsConfig, LogConfig, RpcConfig};
use crate::rpc::RpcConnection;
use crate::storage::StorageManager;
use slog::{Drain, Level, Logger};
use slog_term;
use std::error::Error;
use std::io::Write;
use tokio::spawn;
use tokio::sync::mpsc::{self, UnboundedReceiver};

use tokio::{select, signal::unix::signal, signal::unix::SignalKind};
use tokio_util::sync::CancellationToken;

#[allow(dead_code)]
pub struct Grader {
    config: GraderConfig,
    logger: Logger,
    rpc: RpcConnection,
    storage_manager: StorageManager,

    cancellation_token: CancellationToken,
}

impl Grader {
    pub fn new(config: GraderConfig) -> Result<Grader, Box<dyn Error>> {
        let logger = Self::setup_logger(&config.log);
        let cancellation_token = Self::setup_signals_handler(&logger);
        let storage_manager = StorageManager::new(config.locations.clone())?;

        let rpc = Self::setup_rpc(
            &config.rpc,
            &config.jobs,
            &logger,
            cancellation_token.child_token(),
            storage_manager.clone(),
        );

        let grader = Grader {
            config,
            logger,
            rpc,
            cancellation_token,
            storage_manager,
        };
        info!(grader.logger, "Grader initialized");
        Ok(grader)
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
        let drain = slog_term::FullFormat::new(decorator)
            .use_local_timestamp()
            .build()
            .fuse();
        let drain = slog_async::Async::new(drain).build().fuse();
        let drain = slog::LevelFilter::new(drain, level).fuse();
        return slog::Logger::root(drain, o!());
    }

    fn setup_rpc(
        rpc_config: &RpcConfig,
        jobs_config: &JobsConfig,
        root_logger: &Logger,
        cancellation_token: CancellationToken,
        storage: StorageManager,
    ) -> RpcConnection {
        let logger = root_logger.new(o!("name" => "rpc_connection"));
        let rpc_connection =
            RpcConnection::new(rpc_config, logger, jobs_config, cancellation_token, storage);
        return rpc_connection;
    }

    fn setup_signals_handler(root_logger: &Logger) -> CancellationToken {
        let token = CancellationToken::new();
        let sig_int_receiver = token.clone();
        let sig_term_receiver = token.clone();
        let mut sig_int_stream = signal(SignalKind::interrupt()).unwrap();
        let mut sig_term_stream = signal(SignalKind::terminate()).unwrap();
        let logger = root_logger.new(o!("name" => "shutdown_monitor"));
        tokio::spawn(async move {
            select! {
                _ = sig_int_stream.recv() => {
                    info!(logger, "Shutting down due to SIGINT received");
                    sig_int_receiver.cancel();
                }
                _ = sig_term_stream.recv() => {
                    info!(logger, "Shutting down due to SIGTERM received");
                    sig_term_receiver.cancel();
                }
            }
        });
        return token;
    }

    pub async fn main(&mut self) -> Result<(), Box<dyn Error>> {
        let pid = std::process::id();
        info!(self.logger, "Started grader serving at PID = {}", pid);
        let rpc = &mut self.rpc;
        let (status_sink, mut status_stream) = mpsc::unbounded_channel::<usize>();
        let (finished_sink, mut finished_stream) = mpsc::unbounded_channel::<Submission>();
        let (mut processor_sink, processor_stream) = mpsc::unbounded_channel::<Submission>();

        let grader_config = self.config.clone();
        let storage_manager = self.storage_manager.clone();
        let jobs_manager_logger = self.logger.new(o!("name" => "jobs_manager"));
        let jobs_manager_cancellation_token = self.cancellation_token.child_token();
        spawn(async {
            let mut jobs_manager = JobsManager::new(
                grader_config,
                storage_manager,
                jobs_manager_logger,
                jobs_manager_cancellation_token,
            );
            jobs_manager
                .serve(status_sink, finished_sink, processor_stream)
                .await
        });

        rpc.serve(
            &mut status_stream,
            &mut finished_stream,
            &mut processor_sink,
        )
        .await
    }
}

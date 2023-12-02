use std::path::{Path, PathBuf};

use slog::Level;
use yaml_rust::yaml;

use super::{k, FromYaml};

#[derive(Clone)]
pub struct LogConfig {
    pub path: std::path::PathBuf,
    pub level: Level,
}

impl Default for LogConfig {
    fn default() -> LogConfig {
        LogConfig {
            path: PathBuf::new(),
            level: Level::Info,
        }
    }
}

impl FromYaml for LogConfig {
    fn from_yaml(_config_file_dir: &Path, root: &yaml::Hash) -> LogConfig {
        let mut config = LogConfig::default();
        if root.contains_key(&k("path")) {
            config.path = PathBuf::from(root[&k("path")].as_str().unwrap())
        }
        if root.contains_key(&k("level")) {
            config.level = log_level_from_string(&root[&k("level")].as_str().unwrap().to_string())
        }
        return config;
    }
}

pub fn log_level_from_string(s: &String) -> Level {
    match s.to_lowercase().as_str() {
        "info" => Level::Info,
        "fatal" => Level::Critical,
        "critical" => Level::Critical,
        "debug" => Level::Debug,
        "error" => Level::Error,
        "warning" => Level::Warning,
        "warn" => Level::Warning,
        "trace" => Level::Trace,
        _ => panic!("wrong log level {s}"),
    }
}

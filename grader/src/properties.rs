#[allow(unused_imports)]
use clap::ArgMatches;
use num_cpus;
use slog::Level;
use std::{
    fs::read_to_string,
    path::{Path, PathBuf},
};
use uris::Uri;
use yaml_rust::{yaml, Yaml, YamlLoader};

#[derive(Clone)]
pub struct LogConfig {
    pub path: std::path::PathBuf,
    pub level: Level,
}

#[derive(Clone)]
pub struct JobsConfig {
    pub workers: usize,
    pub arch_specific_only: bool,
    pub name: String,
}

#[derive(Clone)]
pub struct EndpointsConfig {
    pub courses_content_uri: Uri,
    pub submissions_uri: Uri,
}

#[derive(Clone)]
pub struct RpcConfig {
    pub endpoints: EndpointsConfig,
    pub private_token: String,
}

#[derive(Clone)]
pub struct LocationsConfig {
    pub working_directory: PathBuf,
    pub cache_directory: PathBuf,
}

#[derive(Clone)]
pub struct GraderConfig {
    pub log: LogConfig,
    pub rpc: RpcConfig,
    pub jobs: JobsConfig,
    pub locations: LocationsConfig,
}

impl EndpointsConfig {
    pub fn from_yaml(root: &yaml::Hash) -> EndpointsConfig {
        EndpointsConfig {
            courses_content_uri: Uri::parse(
                root[&Yaml::String("courses_content".to_string())]
                    .as_str()
                    .expect("No courses_content RPC URI set in config file"),
            )
            .expect("Invalid courses_content RPC URI in config file"),
            submissions_uri: Uri::parse(
                root[&Yaml::String("submissions".to_string())]
                    .as_str()
                    .expect("No submissions RPC URI set in config file"),
            )
            .expect("Invalid submissions RPC URI in config file"),
        }
    }
}

impl JobsConfig {
    pub fn default_value() -> JobsConfig {
        JobsConfig {
            workers: num_cpus::get(),
            arch_specific_only: false,
            name: "default".to_string(),
        }
    }

    pub fn from_yaml(root: &yaml::Hash) -> JobsConfig {
        let workers_key = &Yaml::String("workers".to_string());
        let arch_key = &Yaml::String("arch_specific_only".to_string());
        let mut workers = if root.contains_key(workers_key) {
            root[workers_key].as_i64().unwrap()
        } else {
            0
        } as usize;
        let arch = if root.contains_key(arch_key) {
            root[arch_key].as_bool().unwrap()
        } else {
            false
        };
        let max_workers = num_cpus::get();
        if workers == 0 || workers > max_workers {
            workers = max_workers;
        }
        return JobsConfig {
            workers,
            arch_specific_only: arch,
            name: "default".to_string(),
        };
    }
}

impl RpcConfig {
    pub fn from_yaml(conf_file_dir: &Path, root: &yaml::Hash) -> RpcConfig {
        let endpoints_node = root[&Yaml::String("endpoints".to_string())]
            .as_hash()
            .expect("No RPC in config file");
        let private_token_file_key = &Yaml::String("private_token_file".to_string());
        let private_token_key = &Yaml::String("private_token".to_string());
        let private_token = if root.contains_key(private_token_file_key) {
            let file_path = resolve_relative(
                &conf_file_dir,
                root[private_token_file_key].as_str().unwrap(),
            );
            Self::read_private_token_file(&file_path)
        } else {
            root[private_token_key].as_str().unwrap().to_string()
        };
        RpcConfig {
            endpoints: EndpointsConfig::from_yaml(&endpoints_node),
            private_token,
        }
    }

    fn read_private_token_file(file_path: &Path) -> String {
        std::fs::read_to_string(file_path)
            .expect("Can't read RPC private token file ")
            .trim()
            .to_string()
    }
}

impl LocationsConfig {
    pub fn from_yaml(conf_file_dir: &Path, root: &yaml::Hash) -> LocationsConfig {
        let working_directory_key = &Yaml::String("working_directory".to_string());
        let cache_directory_key = &Yaml::String("cache_directory".to_string());
        let working_directory = resolve_relative(
            &conf_file_dir,
            root[working_directory_key]
                .as_str()
                .expect("Required location->working_directory path"),
        );
        let cache_directory = resolve_relative(
            &conf_file_dir,
            root[cache_directory_key]
                .as_str()
                .expect("Required location->cache_directory path"),
        );
        LocationsConfig {
            working_directory,
            cache_directory,
        }
    }
}

impl LogConfig {
    pub fn default_value() -> LogConfig {
        LogConfig {
            path: PathBuf::new(),
            level: Level::Info,
        }
    }
    pub fn from_yaml(root: &yaml::Hash) -> LogConfig {
        let mut config = LogConfig::default_value();
        let path_key = &Yaml::String("path".to_string());
        let level_key = &Yaml::String("level".to_string());
        if root.contains_key(path_key) {
            config.path = PathBuf::from(root[path_key].as_str().unwrap())
        }
        if root.contains_key(level_key) {
            config.level = log_level_from_string(&root[level_key].as_str().unwrap().to_string())
        }
        return config;
    }
}

fn log_level_from_string(s: &String) -> Level {
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

impl GraderConfig {
    pub fn from_yaml(conf_file_dir: &Path, root: &yaml::Hash) -> GraderConfig {
        let log_key = &Yaml::String("log".to_string());
        let rpc_key = &Yaml::String("rpc".to_string());
        let jobs_key = &Yaml::String("jobs".to_string());
        let locations_key = &Yaml::String("locations".to_string());
        let mut config = GraderConfig {
            log: LogConfig::default_value(),
            rpc: RpcConfig::from_yaml(conf_file_dir, root[rpc_key].as_hash().unwrap()),
            jobs: JobsConfig::default_value(),
            locations: LocationsConfig::from_yaml(
                conf_file_dir,
                root[locations_key].as_hash().unwrap(),
            ),
        };
        if root.contains_key(log_key) {
            config.log = LogConfig::from_yaml(root[log_key].as_hash().unwrap());
        }
        if root.contains_key(jobs_key) {
            config.jobs = JobsConfig::from_yaml(root[jobs_key].as_hash().unwrap());
        }
        return config;
    }

    pub fn from_yaml_file(path: &PathBuf) -> GraderConfig {
        let yaml_data = read_to_string(&path).unwrap();
        let docs = YamlLoader::load_from_str(yaml_data.as_str()).unwrap();
        let doc = &docs[0];
        let root = doc.as_hash().unwrap();
        let conf_file_dir = path.parent().unwrap();
        return GraderConfig::from_yaml(&conf_file_dir, root);
    }

    pub fn from_args(args: ArgMatches) -> GraderConfig {
        let config_file = args.get_one::<String>("config").unwrap();
        let mut config: GraderConfig = GraderConfig::from_yaml_file(&PathBuf::from(config_file));
        if let Some(s) = args.get_one::<String>("log-path") {
            config.log.path = PathBuf::from(s)
        }
        if let Some(s) = args.get_one::<String>("log-level") {
            config.log.level = log_level_from_string(s)
        }
        if let Some(s) = args.get_one::<String>("name") {
            config.jobs.name = s.to_string();
        }
        return config;
    }
}

fn resolve_relative<P>(base_path: &Path, part: &P) -> PathBuf
where
    P: ToString + ?Sized,
{
    if Path::new(&part.to_string()).is_absolute() {
        return PathBuf::from(part.to_string());
    }
    let joined = base_path.join(part.to_string());
    return joined;
}

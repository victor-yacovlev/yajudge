use std::{
    fs::read_to_string,
    path::{Path, PathBuf},
};

use clap::ArgMatches;
use yaml_rust::{yaml, YamlLoader};

use crate::generated::yajudge::GradingLimits;

use super::{
    build_props::BuildProperties,
    jobs_conf::JobsConfig,
    k,
    locations_conf::LocationsConfig,
    log_conf::{log_level_from_string, LogConfig},
    rpc_conf::RpcConfig,
    FromYaml,
};

#[derive(Clone)]
pub struct GraderConfig {
    pub log: LogConfig,
    pub rpc: RpcConfig,
    pub jobs: JobsConfig,
    pub locations: LocationsConfig,
    pub default_limits: GradingLimits,
    pub default_build_properties: BuildProperties,
}

impl FromYaml for GraderConfig {
    fn from_yaml(conf_file_dir: &Path, root: &yaml::Hash) -> GraderConfig {
        let mut config = GraderConfig {
            log: LogConfig::default(),
            rpc: RpcConfig::from_yaml(conf_file_dir, root[&k("rpc")].as_hash().unwrap()),
            jobs: JobsConfig::default(),
            locations: LocationsConfig::from_yaml(
                conf_file_dir,
                root[&k("locations")].as_hash().unwrap(),
            ),
            default_limits: GradingLimits::default_value(),
            default_build_properties: BuildProperties::default(),
        };
        if root.contains_key(&k("log")) {
            config.log = LogConfig::from_yaml(&conf_file_dir, root[&k("log")].as_hash().unwrap());
        }
        if root.contains_key(&k("jobs")) {
            config.jobs =
                JobsConfig::from_yaml(&conf_file_dir, root[&k("jobs")].as_hash().unwrap());
        }
        if root.contains_key(&k("default_limits")) {
            config.default_limits = GradingLimits::from_yaml(
                &conf_file_dir,
                root[&k("default_limits")].as_hash().unwrap(),
            );
        }
        return config;
    }
}

impl GraderConfig {
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

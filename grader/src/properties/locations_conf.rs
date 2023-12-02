use std::path::{Path, PathBuf};

use yaml_rust::yaml;

use super::{k, resolve_relative, FromYaml};

#[derive(Clone)]
pub struct LocationsConfig {
    pub working_directory: PathBuf,
    pub cache_directory: PathBuf,
    pub system_root: PathBuf,
}

impl FromYaml for LocationsConfig {
    fn from_yaml(conf_file_dir: &Path, root: &yaml::Hash) -> LocationsConfig {
        let working_directory = resolve_relative(
            &conf_file_dir,
            root[&k("working_directory")]
                .as_str()
                .expect("Required location->working_directory path"),
        );
        let cache_directory = resolve_relative(
            &conf_file_dir,
            root[&k("cache_directory")]
                .as_str()
                .expect("Required location->cache_directory path"),
        );
        let system_root = resolve_relative(
            &conf_file_dir,
            root[&k("system_environment")]
                .as_str()
                .expect("Required location->system_environment path"),
        );
        LocationsConfig {
            working_directory,
            cache_directory,
            system_root,
        }
    }
}

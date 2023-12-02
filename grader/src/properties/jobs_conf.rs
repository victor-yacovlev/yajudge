use std::path::Path;

use yaml_rust::yaml;

use super::{k, FromYaml};

#[derive(Clone)]
pub struct JobsConfig {
    pub workers: usize,
    pub arch_specific_only: bool,
    pub name: String,
}

impl Default for JobsConfig {
    fn default() -> Self {
        JobsConfig {
            workers: num_cpus::get(),
            arch_specific_only: false,
            name: "default".to_string(),
        }
    }
}

impl FromYaml for JobsConfig {
    fn from_yaml(_conf_file_dir: &Path, root: &yaml::Hash) -> JobsConfig {
        let mut workers = if root.contains_key(&k("workers")) {
            root[&k("workers")].as_i64().unwrap()
        } else {
            0
        } as usize;
        let arch = if root.contains_key(&k("arch_specific_only")) {
            root[&k("arch_specific_only")].as_bool().unwrap()
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

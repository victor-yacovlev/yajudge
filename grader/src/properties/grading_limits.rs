use std::path::Path;

use yaml_rust::{yaml, Yaml};

use crate::generated::yajudge::GradingLimits;

use super::{k, FromYaml, ToYaml, UpdatedWith};

impl ToYaml for GradingLimits {
    fn to_yaml(&self) -> yaml::Hash {
        let mut result = yaml::Hash::new();
        result.insert(
            k("stack_size_limit_mb"),
            Yaml::Integer(self.stack_size_limit_mb as i64),
        );
        result.insert(
            k("memory_max_limit_mb"),
            Yaml::Integer(self.memory_max_limit_mb as i64),
        );
        result.insert(
            k("cpu_time_limit_sec"),
            Yaml::Integer(self.cpu_time_limit_sec as i64),
        );
        result.insert(
            k("real_time_limit_sec"),
            Yaml::Integer(self.real_time_limit_sec as i64),
        );
        result.insert(
            k("proc_count_limit"),
            Yaml::Integer(self.proc_count_limit as i64),
        );
        result.insert(
            k("fd_count_limit"),
            Yaml::Integer(self.fd_count_limit as i64),
        );
        result.insert(
            k("stdout_size_limit_mb"),
            Yaml::Integer(self.stdout_size_limit_mb as i64),
        );
        result.insert(
            k("stderr_size_limit_mb"),
            Yaml::Integer(self.stderr_size_limit_mb as i64),
        );
        result.insert(k("allow_network"), Yaml::Boolean(self.allow_network));
        result.insert(
            k("new_proc_delay_msec"),
            Yaml::Integer(self.new_proc_delay_msec as i64),
        );
        return result;
    }
}

impl FromYaml for GradingLimits {
    fn from_yaml(_conf_file_dir: &Path, root: &yaml::Hash) -> Self {
        let mut result = GradingLimits::default();
        if root.contains_key(&k("stack_size_limit_mb")) {
            result.stack_size_limit_mb =
                root[&k("stack_size_limit_mb")].as_i64().unwrap_or_default() as i32;
        }
        if root.contains_key(&k("memory_max_limit_mb")) {
            result.memory_max_limit_mb =
                root[&k("memory_max_limit_mb")].as_i64().unwrap_or_default() as i32;
        }
        if root.contains_key(&k("cpu_time_limit_sec")) {
            result.cpu_time_limit_sec =
                root[&k("cpu_time_limit_sec")].as_i64().unwrap_or_default() as i32;
        }
        if root.contains_key(&k("real_time_limit_sec")) {
            result.real_time_limit_sec =
                root[&k("real_time_limit_sec")].as_i64().unwrap_or_default() as i32;
        }
        if root.contains_key(&k("proc_count_limit")) {
            result.proc_count_limit =
                root[&k("proc_count_limit")].as_i64().unwrap_or_default() as i32;
        }
        if root.contains_key(&k("fd_count_limit")) {
            result.fd_count_limit = root[&k("fd_count_limit")].as_i64().unwrap_or_default() as i32;
        }
        if root.contains_key(&k("stdout_size_limit_mb")) {
            result.stdout_size_limit_mb = root[&k("stdout_size_limit_mb")]
                .as_i64()
                .unwrap_or_default() as i32;
        }
        if root.contains_key(&k("stderr_size_limit_mb")) {
            result.stderr_size_limit_mb = root[&k("stderr_size_limit_mb")]
                .as_i64()
                .unwrap_or_default() as i32;
        }
        if root.contains_key(&k("allow_network")) {
            result.allow_network = root[&k("allow_network")].as_bool().unwrap_or_default();
        }
        if root.contains_key(&k("new_proc_delay_msec")) {
            result.new_proc_delay_msec =
                root[&k("new_proc_delay_msec")].as_i64().unwrap_or_default() as i32;
        }
        return result;
    }
}

impl UpdatedWith for GradingLimits {
    fn updated_with(&self, other: &Self) -> Self {
        let mut result = self.clone();
        if other.stack_size_limit_mb != 0 {
            result.stack_size_limit_mb = other.stack_size_limit_mb;
        }
        if other.memory_max_limit_mb != 0 {
            result.memory_max_limit_mb = other.memory_max_limit_mb;
        }
        if other.cpu_time_limit_sec != 0 {
            result.cpu_time_limit_sec = other.cpu_time_limit_sec;
        }
        if other.real_time_limit_sec != 0 {
            result.real_time_limit_sec = other.real_time_limit_sec;
        }
        if other.proc_count_limit != 0 {
            result.proc_count_limit = other.proc_count_limit;
        }
        if other.fd_count_limit != 0 {
            result.fd_count_limit = other.fd_count_limit;
        }
        if other.stdout_size_limit_mb != 0 {
            result.stdout_size_limit_mb = other.stdout_size_limit_mb;
        }
        if other.memory_max_limit_mb != 0 {
            result.stderr_size_limit_mb = other.stderr_size_limit_mb;
        }
        if other.allow_network {
            result.allow_network = true;
        }
        return result;
    }
}

impl GradingLimits {
    pub fn default_value() -> GradingLimits {
        GradingLimits {
            stack_size_limit_mb: 4,
            memory_max_limit_mb: 64,
            cpu_time_limit_sec: 1,
            real_time_limit_sec: 5,
            proc_count_limit: 20,
            fd_count_limit: 20,
            stdout_size_limit_mb: 1,
            stderr_size_limit_mb: 1,
            allow_network: false,
            new_proc_delay_msec: 0,
        }
    }
}

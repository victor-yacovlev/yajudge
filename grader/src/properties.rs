pub mod build_props;
pub mod grader_conf;
pub mod grading_limits;
pub mod grading_options;
pub mod jobs_conf;
pub mod locations_conf;
pub mod log_conf;
pub mod rpc_conf;
pub mod submission;

use std::path::{Path, PathBuf};

use yaml_rust::{yaml, Yaml};

pub trait FromYaml {
    fn from_yaml(conf_file_dir: &Path, root: &yaml::Hash) -> Self;
}

pub trait ToYaml {
    fn to_yaml(&self) -> yaml::Hash;
}

pub trait UpdatedWith: Sized {
    fn updated_with(&self, other: &Self) -> Self;
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

fn k(s: impl ToString) -> Yaml {
    let string = s.to_string();
    Yaml::String(string)
}

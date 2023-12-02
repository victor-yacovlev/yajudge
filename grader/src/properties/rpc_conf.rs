use std::path::Path;

use uris::Uri;
use yaml_rust::{yaml, Yaml};

use super::{k, resolve_relative, FromYaml};

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

impl FromYaml for EndpointsConfig {
    fn from_yaml(_conf_file_dir: &Path, root: &yaml::Hash) -> EndpointsConfig {
        EndpointsConfig {
            courses_content_uri: Uri::parse(
                root[&k("courses_content")]
                    .as_str()
                    .expect("No courses_content RPC URI set in config file"),
            )
            .expect("Invalid courses_content RPC URI in config file"),
            submissions_uri: Uri::parse(
                root[&k("submissions")]
                    .as_str()
                    .expect("No submissions RPC URI set in config file"),
            )
            .expect("Invalid submissions RPC URI in config file"),
        }
    }
}

impl FromYaml for RpcConfig {
    fn from_yaml(conf_file_dir: &Path, root: &yaml::Hash) -> RpcConfig {
        let endpoints_node = root[&Yaml::String("endpoints".to_string())]
            .as_hash()
            .expect("No RPC in config file");
        let private_token = if root.contains_key(&k("private_token_file")) {
            let file_path = resolve_relative(
                &conf_file_dir,
                root[&k("private_token_file")].as_str().unwrap(),
            );
            Self::read_private_token_file(&file_path)
        } else {
            root[&k("private_token")].as_str().unwrap().to_string()
        };
        RpcConfig {
            endpoints: EndpointsConfig::from_yaml(&conf_file_dir, &endpoints_node),
            private_token,
        }
    }
}

impl RpcConfig {
    fn read_private_token_file(file_path: &Path) -> String {
        std::fs::read_to_string(file_path)
            .expect("Can't read RPC private token file ")
            .trim()
            .to_string()
    }
}

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

use crate::{
    generated::yajudge::{
        BuildSystem, CodeStyle, Course, File, FileSet, GradingLimits, GradingOptions, Submission,
        TestCase,
    },
    storage::StorageManager,
};

pub trait FromYaml {
    fn from_yaml(conf_file_dir: &Path, root: &yaml::Hash) -> Self;
}

pub trait ToYaml {
    fn to_yaml(&self) -> yaml::Hash;
}

pub trait UpdatedWith: Sized {
    fn updated_with(&self, other: &Self) -> Self;
}

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
    pub system_root: PathBuf,
}

#[derive(Clone)]
pub struct LanguageBuildProperties {
    pub compiler: String,
    pub compiler_options: Vec<String>,
    pub sanitizers: Option<Vec<String>>,
}

#[derive(Clone)]
pub struct BuildProperties {
    pub c: LanguageBuildProperties,
    pub cxx: LanguageBuildProperties,
    pub s: LanguageBuildProperties,
    pub java: LanguageBuildProperties,
}

#[derive(Clone)]
pub struct GraderConfig {
    pub log: LogConfig,
    pub rpc: RpcConfig,
    pub jobs: JobsConfig,
    pub locations: LocationsConfig,
    pub default_limits: GradingLimits,
    pub default_build_properties: BuildProperties,
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

impl Default for BuildProperties {
    fn default() -> Self {
        Self {
            c: LanguageBuildProperties {
                compiler: "clang".to_string(),
                compiler_options: Vec::from([
                    "-O2".to_string(),
                    "-g".to_string(),
                    "-Werror".to_string(),
                ]),
                sanitizers: Some(Vec::from(["undefined".to_string(), "address".to_string()])),
            },
            cxx: LanguageBuildProperties {
                compiler: "clang++".to_string(),
                compiler_options: Vec::from([
                    "-O2".to_string(),
                    "-g".to_string(),
                    "-Werror".to_string(),
                ]),
                sanitizers: Some(Vec::from(["undefined".to_string(), "address".to_string()])),
            },
            s: LanguageBuildProperties {
                compiler: "clang".to_string(),
                compiler_options: Vec::from([
                    "-O0".to_string(),
                    "-g".to_string(),
                    "-Werror".to_string(),
                ]),
                sanitizers: None,
            },
            java: LanguageBuildProperties {
                compiler: "javac".to_string(),
                compiler_options: Vec::from(["-g".to_string(), "-Werror".to_string()]),
                sanitizers: None,
            },
        }
    }
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

impl ToYaml for GradingOptions {
    fn to_yaml(&self) -> yaml::Hash {
        let mut result = yaml::Hash::new();
        if let Some(limits) = self.limits.as_ref() {
            result.insert(k("limits"), Yaml::Hash(GradingLimits::to_yaml(&limits)));
        }
        let build_system =
            BuildSystem::try_from(self.build_system).expect("Unknown build_system value");
        result.insert(
            k("build_system"),
            Yaml::String(build_system.as_str_name().to_string()),
        );

        // TODO implement other options

        let code_styles = &self.code_styles;
        let mut style_checkers = yaml::Array::new();
        for code_style in code_styles {
            if let Some(style_file) = &code_style.style_file {
                let mut entry = yaml::Hash::new();
                let language = &code_style.source_file_suffix;
                let file_name = &style_file.name;
                entry.insert(k("language"), Yaml::String(language.clone()));
                entry.insert(k("style_file"), Yaml::String(file_name.clone()));
                style_checkers.insert(style_checkers.len(), Yaml::Hash(entry));
            }
        }
        if style_checkers.len() > 0 {
            result.insert(k("style_checkers"), Yaml::Array(style_checkers));
        }

        let tests_cases = &self.test_cases;
        let mut tests = yaml::Array::new();
        let mut test_number = 1;
        for test_case in tests_cases {
            let mut test = yaml::Hash::new();
            if let Some(stdin_file) = test_case.stdin_data.as_ref() {
                test.insert(k("stdin"), Yaml::String(stdin_file.name.clone()));
            }
            if let Some(stdout_file) = test_case.stdout_reference.as_ref() {
                test.insert(k("stdout"), Yaml::String(stdout_file.name.clone()));
            }
            if let Some(stderr_file) = test_case.stderr_reference.as_ref() {
                test.insert(k("stderr"), Yaml::String(stderr_file.name.clone()));
            }
            if !test_case.command_line_arguments.is_empty() {
                test.insert(k("args"), Yaml::String(format!("{:03}.args", test_number)));
            }
            tests.insert(test_number - 1, Yaml::Hash(test));
            test_number += 1;
        }
        result.insert(k("tests"), Yaml::Array(tests));

        return result;
    }
}

impl FromYaml for GradingOptions {
    fn from_yaml(conf_file_dir: &Path, root: &yaml::Hash) -> Self {
        let mut result = GradingOptions::default();
        if root.contains_key(&k("limits")) {
            let limits_node = root[&k("limits")].as_hash();
            if let Some(hash) = limits_node {
                result.limits = Some(GradingLimits::from_yaml(conf_file_dir, hash));
            }
        }
        if root.contains_key(&k("build_system")) {
            let build_system_str = root[&k("build_system")].as_str().unwrap();
            let build_system = BuildSystem::from_str_name(&build_system_str)
                .expect("Unknown build system string value");
            result.build_system = build_system.into();
        }
        if root.contains_key(&k("style_checkers")) {
            let style_checkers = root[&k("style_checkers")].as_vec().unwrap();
            for entry in style_checkers {
                let language = entry.as_hash().unwrap()[&k("language")].as_str().unwrap();
                let style_file = entry.as_hash().unwrap()[&k("style_file")].as_str().unwrap();
                let mut file = File::default();
                file.name = style_file.to_string();
                let mut code_style = CodeStyle::default();
                code_style.source_file_suffix = language.to_string();
                code_style.style_file = Some(file);
                result
                    .code_styles
                    .insert(result.code_styles.len(), code_style);
            }
        }
        if root.contains_key(&k("tests")) {
            let tests = root[&k("tests")].as_vec().unwrap();
            for test in tests {
                let test_info = test.as_hash().unwrap();
                let mut test_case = TestCase::default();
                if test_info.contains_key(&k("stdin")) {
                    let mut file = File::default();
                    file.name = test_info[&k("stdin")].as_str().unwrap().to_string();
                    test_case.stdin_data = Some(file);
                }
                if test_info.contains_key(&k("stdout")) {
                    let mut file = File::default();
                    file.name = test_info[&k("stdout")].as_str().unwrap().to_string();
                    test_case.stdout_reference = Some(file);
                }
                if test_info.contains_key(&k("stderr")) {
                    let mut file = File::default();
                    file.name = test_info[&k("stderr")].as_str().unwrap().to_string();
                    test_case.stderr_reference = Some(file);
                }
                if test_info.contains_key(&k("args")) {
                    let args_name = test_info[&k("args")].as_str().unwrap();
                    let args_path = conf_file_dir
                        .with_file_name("lowerdir")
                        .join("tests")
                        .join(args_name);
                    let args = StorageManager::load_string(&args_path)
                        .expect(format!("Can't read {}", &args_path.to_str().unwrap()).as_str());
                    test_case.command_line_arguments = args;
                }
                result.test_cases.insert(result.test_cases.len(), test_case);
            }
        }
        return result;
    }
}

impl UpdatedWith for GradingOptions {
    fn updated_with(&self, other: &Self) -> Self {
        let mut result = self.clone();
        if let Some(limits) = other.limits.as_ref() {
            result.limits = match self.limits.as_ref() {
                None => other.limits.clone(),
                Some(l) => Some(l.updated_with(&limits)),
            }
        }
        return result;
    }
}

impl ToYaml for Submission {
    fn to_yaml(&self) -> yaml::Hash {
        let mut solution_files = yaml::Array::new();
        for file in &self.solution_files.as_ref().unwrap().files {
            let file_name = &file.name;
            solution_files.insert(solution_files.len(), Yaml::String(file_name.clone()));
        }
        let mut result = yaml::Hash::new();
        result.insert(k("id"), Yaml::Integer(self.id));
        result.insert(
            k("course_id"),
            Yaml::String(self.course.as_ref().unwrap().data_id.clone()),
        );
        result.insert(k("problem_id"), Yaml::String(self.problem_id.clone()));
        result.insert(k("solution_files"), Yaml::Array(solution_files));
        return result;
    }
}

impl FromYaml for Submission {
    fn from_yaml(_conf_file_dir: &Path, root: &yaml::Hash) -> Self {
        let course_id = if root.contains_key(&k("course_id")) {
            root[&k("course_id")].as_str().unwrap().to_string()
        } else {
            String::new()
        };
        let problem_id = if root.contains_key(&k("problem_id")) {
            root[&k("problem_id")].as_str().unwrap().to_string()
        } else {
            String::new()
        };
        let mut result = Submission::default();
        let mut course = Course::default();
        course.data_id = course_id;
        result.problem_id = problem_id;
        result.course = Some(course);
        let id = root[&k("id")].as_i64().expect("No id in submission");
        result.id = id;
        if root.contains_key(&k("solution_files")) {
            let list = root[&k("solution_files")]
                .as_vec()
                .expect("No solution files in submission");
            let mut file_set = FileSet::default();
            for entry in list {
                let file_name = entry.as_str().unwrap();
                let mut file = File::default();
                file.name = file_name.to_string();
                file_set.files.insert(file_set.files.len(), file);
            }
            result.solution_files = Some(file_set);
        }
        return result;
    }
}

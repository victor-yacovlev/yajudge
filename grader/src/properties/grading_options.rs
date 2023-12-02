use std::path::Path;

use yaml_rust::{yaml, Yaml};

use crate::{
    generated::yajudge::{BuildSystem, CodeStyle, File, GradingLimits, GradingOptions, TestCase},
    storage::StorageManager,
};

use super::{k, FromYaml, ToYaml, UpdatedWith};

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

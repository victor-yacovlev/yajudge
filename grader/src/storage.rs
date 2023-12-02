#[allow(unused_imports)]
use crate::{
    generated::yajudge::{File, GradingOptions, ProblemContentResponse, Submission},
    properties::{locations_conf::LocationsConfig, FromYaml, ToYaml},
};
use anyhow::Result;
use libflate::gzip;
use std::{
    fs::Permissions,
    io::Read,
    os::unix::prelude::PermissionsExt,
    path::{Path, PathBuf},
};

#[derive(Clone)]
pub struct StorageManager {
    pub config: LocationsConfig,
}

impl StorageManager {
    pub fn new(config: LocationsConfig) -> Result<StorageManager> {
        Self::mkdir(&config.cache_directory)?;
        Self::mkdir(&config.working_directory)?;
        let storage = StorageManager { config };

        Ok(storage)
    }

    pub fn mkdir(path: &Path) -> Result<()> {
        std::fs::create_dir_all(path)?;

        // TODO set permissions for all middle parts of path
        std::fs::set_permissions(path, Permissions::from_mode(0o770))?;

        Ok(())
    }

    pub fn get_problem_timestamp(&self, course_id: &String, problem_id: &String) -> Result<i64> {
        let problem_root = self.get_problem_root(course_id, problem_id);
        let timestamp_path = problem_root.join("timestamp.txt");
        let content_bytes = std::fs::read(timestamp_path)?;
        let content_string = String::from_utf8(content_bytes)?;
        let stamp = content_string.trim().parse::<i64>()?;

        Ok(stamp)
    }

    pub fn get_problem_root(&self, course_id: &String, problem_id: &String) -> PathBuf {
        let cache_root = &self.config.cache_directory.as_path();
        let problem_dir = problem_id.replace(":", "/");

        cache_root.join(course_id).join(problem_dir)
    }

    pub fn get_submission_root(&self, submission_id: i64) -> PathBuf {
        let work_root = &self.config.working_directory.as_path();
        let sub_dir = format!("{:06}", submission_id);

        work_root.join(&sub_dir)
    }

    pub fn get_system_root(&self) -> PathBuf {
        self.config.system_root.clone()
    }

    pub fn get_submission(&self, submission_root: &Path) -> Submission {
        let submission_yaml_path = submission_root.join("submission.yaml");

        Self::load_yaml(&submission_yaml_path).expect(
            format!(
                "Can't read submission metadata from {}",
                submission_yaml_path.as_os_str().to_str().unwrap()
            )
            .as_str(),
        )
    }

    pub fn store_problem(&self, problem_content: ProblemContentResponse) -> Result<()> {
        let problem_root =
            self.get_problem_root(&problem_content.course_data_id, &problem_content.problem_id);
        let _ = std::fs::remove_dir_all(&problem_root);
        let build_dir = problem_root.join("lowerdir").join("build");
        let tests_dir = problem_root.join("lowerdir").join("tests");
        Self::mkdir(&build_dir)?;
        Self::mkdir(&tests_dir)?;

        let grading_options = problem_content
            .data
            .as_ref()
            .unwrap() // Guaranteed if problem is subject to store
            .grading_options
            .as_ref()
            .unwrap(); // Guaranteed by fetch method

        let tests_cases = &grading_options.test_cases;

        let mut test_number = 1;
        for test_case in tests_cases {
            Self::store_file_to(&tests_dir, &test_case.stdin_data.as_ref(), true)?;
            Self::store_file_to(&tests_dir, &test_case.stdout_reference.as_ref(), true)?;
            Self::store_file_to(&tests_dir, &test_case.stderr_reference.as_ref(), true)?;
            if !test_case.command_line_arguments.is_empty() {
                let file_name = tests_dir.join(format!("{:03}.args", test_number));
                Self::store_plain_text(&file_name, &test_case.command_line_arguments)?;
            }
            test_number += 1;
        }

        let code_styles = &grading_options.code_styles;
        for code_style in code_styles {
            Self::store_file_to(&build_dir, &code_style.style_file.as_ref(), false)?;
        }

        let options_path = problem_root.join("grading_options.yaml");
        Self::store_yaml(options_path.as_path(), grading_options)?;

        let timestamp_data = format!("{}\n", problem_content.last_modified);
        let timestamp_path = problem_root.join("timestamp.txt");
        Self::store_plain_text(timestamp_path.as_path(), &timestamp_data)?;

        Ok(())
    }

    pub fn store_submission(&self, submission: &Submission) -> Result<i64> {
        let submission_root = self.get_submission_root(submission.id);
        let build_root = submission_root.join("upperdir").join("build");

        let files = &submission.solution_files.as_ref().unwrap();
        let mut files_list = String::new();
        for file in &files.files {
            files_list.push_str(&format!("{}\n", file.name));
            Self::store_file_to(&build_root, &Some(file), false)?;
        }

        Self::store_yaml(&submission_root.join("submission.yaml"), submission)?;

        Ok(submission.id)
    }

    pub fn store_file_to(dir_path: &Path, file: &Option<&File>, gzipped: bool) -> Result<()> {
        match file {
            None => Ok(()),
            Some(file) => {
                let file_path = dir_path.join(&file.name);
                let file_data = &file.data;
                Self::store_binary(&file_path, file_data, gzipped)
            }
        }
    }

    fn store_yaml(path: &Path, data: &impl ToYaml) -> Result<()> {
        let yaml_data = yaml_rust::Yaml::Hash(data.to_yaml());
        let mut buffer = String::new();
        let mut emitter = yaml_rust::YamlEmitter::new(&mut buffer);
        emitter.dump(&yaml_data)?;

        Self::store_plain_text(path, &buffer)
    }

    fn store_plain_text<T>(path: &Path, data: &T) -> Result<()>
    where
        T: ToString,
    {
        Self::store_binary(path, &data.to_string().as_bytes(), false)
    }

    pub fn store_binary(path: &Path, data: &[u8], gzipped: bool) -> Result<()> {
        let dir_path = path.parent().unwrap();
        Self::mkdir(&dir_path)?;

        let mut decoded_data = Vec::new();
        let data_to_store = if gzipped {
            let mut decoder = gzip::Decoder::new(data)?;
            decoder.read_to_end(&mut decoded_data)?;
            decoded_data.as_slice()
        } else {
            data
        };
        std::fs::write(path, data_to_store)?;
        std::fs::set_permissions(path, Permissions::from_mode(0o660))?;

        Ok(())
    }

    pub fn get_problem_grading_options(&self, problem_root: &Path) -> Result<GradingOptions> {
        let options_path = problem_root.join("grading_options.yaml");

        Self::load_yaml(&options_path)
    }

    fn load_yaml<T>(path: &Path) -> Result<T>
    where
        T: FromYaml,
    {
        let yaml_string = Self::load_string(path)?;
        match yaml_rust::YamlLoader::load_from_str(yaml_string.as_str()) {
            Err(err) => Err(err.into()),
            Ok(yaml_docs) => {
                if yaml_docs.len() < 1 {
                    bail!("File has no YAML document")
                } else {
                    let doc = &yaml_docs[0];
                    match doc.as_hash() {
                        None => bail!("File has no structured YAML data"),
                        Some(h) => Ok(T::from_yaml(path, h)),
                    }
                }
            }
        }
    }

    pub fn load_string(path: &Path) -> Result<String> {
        let binary_data = Self::load_binary(path)?;
        match String::from_utf8(binary_data) {
            Ok(s) => Ok(s),
            Err(err) => Err(err.into()),
        }
    }

    pub fn load_binary(path: &Path) -> Result<Vec<u8>> {
        match std::fs::read(&path) {
            Ok(data) => Ok(data),
            Err(err) => Err(err.into()),
        }
    }
}

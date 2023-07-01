use crate::{
    generated::yajudge::{File, ProblemContentResponse, Submission},
    properties::LocationsConfig,
};
use libflate::gzip;
use std::{
    error::Error,
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
    pub fn new(config: LocationsConfig) -> Result<StorageManager, Box<dyn Error>> {
        Self::mkdir(&config.cache_directory)?;
        Self::mkdir(&config.working_directory)?;
        let storage = StorageManager { config };

        Ok(storage)
    }

    fn mkdir(path: &Path) -> Result<(), Box<dyn Error>> {
        std::fs::create_dir_all(path)?;

        // TODO set permissions for all middle parts of path
        std::fs::set_permissions(path, Permissions::from_mode(0o770))?;

        Ok(())
    }

    pub fn get_problem_timestamp(
        &self,
        course_id: &String,
        problem_id: &String,
    ) -> Result<i64, Box<dyn Error>> {
        let problem_root = self.get_problem_root(course_id, problem_id);
        let timestamp_path = problem_root.with_file_name(".timestamp");
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

    pub fn store_problem(
        &self,
        problem_content: ProblemContentResponse,
    ) -> Result<(), Box<dyn Error>> {
        let problem_root =
            self.get_problem_root(&problem_content.course_data_id, &problem_content.problem_id);
        let _ = std::fs::remove_dir_all(&problem_root);
        let build_dir = problem_root.join("build");
        let tests_dir = problem_root.join("tests");
        Self::mkdir(&build_dir)?;
        Self::mkdir(&tests_dir)?;

        let tests_cases = problem_content
            .data
            .unwrap() // Guaranteed if problem is subject to store
            .grading_options
            .unwrap() // Guaranteed by fetch method
            .test_cases;

        let mut test_number = 1;
        let mut tests_count = 0;
        for test_case in tests_cases {
            Self::store_file_to(&tests_dir, &test_case.stdin_data.as_ref(), true)?;
            Self::store_file_to(&tests_dir, &test_case.stdout_reference.as_ref(), true)?;
            Self::store_file_to(&tests_dir, &test_case.stderr_reference.as_ref(), true)?;
            if !test_case.command_line_arguments.is_empty() {
                let file_name = tests_dir.join(format!("{:03}.args", test_number));
                Self::store_plain_text(&file_name, &test_case.command_line_arguments)?;
            }
            test_number += 1;
            tests_count += 1;
        }
        Self::store_plain_text(
            &tests_dir.join(".tests_count"),
            &format!("{}\n", tests_count),
        )?;

        let timestamp_data = format!("{}\n", problem_content.last_modified);
        let timestamp_path = problem_root.with_file_name(".timestamp");
        Self::store_plain_text(timestamp_path.as_path(), &timestamp_data)?;

        Ok(())
    }

    pub fn store_submission(&self, submission: &Submission) -> Result<i64, Box<dyn Error>> {
        let submission_root = self.get_submission_root(submission.id);
        let course_id = &submission.course.as_ref().unwrap().data_id;
        let problem_id = submission.problem_id.replace(":", "/");
        Self::store_plain_text(
            &submission_root.join(".problem"),
            &format!("{}/{}", course_id, problem_id),
        )?;

        let files = &submission.solution_files.as_ref().unwrap();
        let mut files_list = String::new();
        for file in &files.files {
            files_list.push_str(&format!("{}\n", file.name));
            Self::store_file_to(&submission_root, &Some(file), false)?;
        }

        Ok(submission.id)
    }

    fn store_file_to(
        dir_path: &Path,
        file: &Option<&File>,
        gzipped: bool,
    ) -> Result<(), Box<dyn Error>> {
        match file {
            None => Ok(()),
            Some(file) => {
                let file_path = dir_path.join(&file.name);
                let file_data = &file.data;
                Self::store_binary(&file_path, file_data, gzipped)
            }
        }
    }

    fn store_plain_text<T>(path: &Path, data: &T) -> Result<(), Box<dyn Error>>
    where
        T: ToString,
    {
        Self::store_binary(path, data.to_string().as_bytes(), false)
    }

    fn store_binary(path: &Path, data: &[u8], gzipped: bool) -> Result<(), Box<dyn Error>> {
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
}

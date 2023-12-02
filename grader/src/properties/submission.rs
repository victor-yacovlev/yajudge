use std::path::Path;

use yaml_rust::{yaml, Yaml};

use crate::generated::yajudge::{Course, File, FileSet, Submission};

use super::{k, FromYaml, ToYaml};

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

use std::{
    collections::{HashMap, HashSet},
    ops::Sub,
};

use super::UpdatedWith;

pub type LanguageBuildProperties = HashMap<String, String>;

#[derive(Clone)]
pub struct BuildProperties {
    pub c: LanguageBuildProperties,
    pub cxx: LanguageBuildProperties,
    pub s: LanguageBuildProperties,
    pub java: LanguageBuildProperties,
}

impl Default for BuildProperties {
    fn default() -> Self {
        let mut c: HashMap<String, String> = HashMap::new();
        let mut cxx: HashMap<String, String> = HashMap::new();
        let mut s: HashMap<String, String> = HashMap::new();
        let mut java: HashMap<String, String> = HashMap::new();

        c.insert("compiler".into(), "clang".into());
        cxx.insert("compiler".into(), "clang++".into());
        s.insert("compiler".into(), "clang".into());
        java.insert("compiler".into(), "javac".into());

        c.insert("compile_options".into(), "-O2 -g -Werror".into());
        cxx.insert("compile_options".into(), "-O2 -g -Werror".into());
        s.insert("compile_options".into(), "-O0 -g -Werror".into());
        java.insert("compile_options".into(), "-g -Werror".into());

        c.insert("sanitizers".into(), "undefined address".into());
        cxx.insert("sanitizers".into(), "undefined address".into());

        Self { c, cxx, s, java }
    }
}

impl UpdatedWith for LanguageBuildProperties {
    fn updated_with(&self, other: &Self) -> Self {
        let mut result = HashMap::<String, String>::new();

        for direct_key in self.keys() {
            let reverse_key: String = "disable_".to_string() + direct_key;
            let self_value = &self[direct_key];
            let mut set = string_to_set(&self_value);
            if other.contains_key(direct_key) {
                let other_value = &other[direct_key];
                let to_add = string_to_set(&other_value);
                set.extend(to_add);
            }
            if other.contains_key(&reverse_key) {
                let other_rev_value = &other[&reverse_key];
                let to_sub = string_to_set(other_rev_value);
                set = set.sub(&to_sub);
            }
            let res_value = set_to_string(&set);
            result.insert(direct_key.clone(), res_value);
        }

        return result;
    }
}

pub fn string_to_set(s: &String) -> HashSet<String> {
    let iter = s.split_whitespace().map(|x| x.to_string());
    return HashSet::from_iter(iter);
}

pub fn set_to_string(s: &HashSet<String>) -> String {
    let iter = s.iter();
    iter.fold(String::new(), |a, b| {
        if a.len() == 0 {
            b.clone()
        } else {
            a.clone() + " " + b
        }
    })
}

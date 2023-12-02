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

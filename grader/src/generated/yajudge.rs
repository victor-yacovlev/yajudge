#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct User {
    #[prost(int64, tag = "1")]
    pub id: i64,
    #[prost(string, tag = "2")]
    pub first_name: ::prost::alloc::string::String,
    #[prost(string, tag = "3")]
    pub last_name: ::prost::alloc::string::String,
    #[prost(string, tag = "4")]
    pub mid_name: ::prost::alloc::string::String,
    #[prost(string, tag = "5")]
    pub email: ::prost::alloc::string::String,
    #[prost(string, tag = "6")]
    pub password: ::prost::alloc::string::String,
    #[prost(string, tag = "7")]
    pub group_name: ::prost::alloc::string::String,
    #[prost(enumeration = "Role", tag = "8")]
    pub default_role: i32,
    #[prost(bool, tag = "9")]
    pub disabled: bool,
    /// alternate way to log in instead of id and email
    #[prost(string, tag = "10")]
    pub login: ::prost::alloc::string::String,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct Session {
    #[prost(string, tag = "1")]
    pub cookie: ::prost::alloc::string::String,
    #[prost(message, optional, tag = "2")]
    pub user: ::core::option::Option<User>,
    /// timestamp
    #[prost(int64, tag = "3")]
    pub start: i64,
    /// initial route on user login
    #[prost(string, tag = "4")]
    pub initial_route: ::prost::alloc::string::String,
    /// to use instead of cookie by microservices
    #[prost(string, tag = "100")]
    pub user_encrypted_data: ::prost::alloc::string::String,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct Nothing {
    #[prost(bool, tag = "1")]
    pub dummy: bool,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct UsersFilter {
    #[prost(enumeration = "Role", tag = "1")]
    pub role: i32,
    #[prost(message, optional, tag = "2")]
    pub user: ::core::option::Option<User>,
    #[prost(message, optional, tag = "3")]
    pub course: ::core::option::Option<Course>,
    #[prost(bool, tag = "4")]
    pub partial_string_match: bool,
    #[prost(bool, tag = "5")]
    pub include_disabled: bool,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct UsersList {
    #[prost(message, repeated, tag = "1")]
    pub users: ::prost::alloc::vec::Vec<User>,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct File {
    #[prost(string, tag = "1")]
    pub name: ::prost::alloc::string::String,
    #[prost(bytes = "vec", tag = "2")]
    pub data: ::prost::alloc::vec::Vec<u8>,
    #[prost(string, tag = "3")]
    pub description: ::prost::alloc::string::String,
    /// unix permissions & 0777, use only for test case files
    #[prost(int32, tag = "4")]
    pub permissions: i32,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct FileSet {
    #[prost(message, repeated, tag = "1")]
    pub files: ::prost::alloc::vec::Vec<File>,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct TextReading {
    #[prost(string, tag = "1")]
    pub id: ::prost::alloc::string::String,
    #[prost(string, tag = "3")]
    pub title: ::prost::alloc::string::String,
    /// text/markdown by default
    #[prost(string, tag = "4")]
    pub content_type: ::prost::alloc::string::String,
    /// encoded in base64 if content-type not starts with 'text/'
    #[prost(string, tag = "5")]
    pub data: ::prost::alloc::string::String,
    #[prost(message, optional, tag = "7")]
    pub resources: ::core::option::Option<FileSet>,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct GradingPlatform {
    /// ARCH_ANY for generic problems
    #[prost(enumeration = "Arch", tag = "1")]
    pub arch: i32,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct GradingLimits {
    #[prost(int32, tag = "1")]
    pub stack_size_limit_mb: i32,
    #[prost(int32, tag = "2")]
    pub memory_max_limit_mb: i32,
    #[prost(int32, tag = "3")]
    pub cpu_time_limit_sec: i32,
    #[prost(int32, tag = "4")]
    pub real_time_limit_sec: i32,
    #[prost(int32, tag = "5")]
    pub proc_count_limit: i32,
    #[prost(int32, tag = "6")]
    pub fd_count_limit: i32,
    #[prost(int32, tag = "7")]
    pub stdout_size_limit_mb: i32,
    #[prost(int32, tag = "8")]
    pub stderr_size_limit_mb: i32,
    #[prost(bool, tag = "9")]
    pub allow_network: bool,
    #[prost(int32, tag = "11")]
    pub new_proc_delay_msec: i32,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct SecurityContext {
    #[prost(string, repeated, tag = "1")]
    pub forbidden_functions: ::prost::alloc::vec::Vec<::prost::alloc::string::String>,
    #[prost(string, repeated, tag = "2")]
    pub allowed_functions: ::prost::alloc::vec::Vec<::prost::alloc::string::String>,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct TestCase {
    /// important in case if partial tests allowed, ignored otherwise
    #[prost(bool, tag = "1")]
    pub blocks_submission: bool,
    /// optional
    #[prost(string, tag = "2")]
    pub description: ::prost::alloc::string::String,
    /// optional
    #[prost(string, tag = "3")]
    pub command_line_arguments: ::prost::alloc::string::String,
    #[prost(message, optional, tag = "4")]
    pub stdin_data: ::core::option::Option<File>,
    #[prost(message, optional, tag = "5")]
    pub stdout_reference: ::core::option::Option<File>,
    #[prost(message, optional, tag = "6")]
    pub stderr_reference: ::core::option::Option<File>,
    /// runtime files
    #[prost(message, optional, tag = "7")]
    pub directory_bundle: ::core::option::Option<File>,
    /// additional files to build solution
    #[prost(message, optional, tag = "8")]
    pub build_directory_bundle: ::core::option::Option<File>,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct GradingOptions {
    /// to match corresponding grader client
    #[prost(message, optional, tag = "1")]
    pub platform_required: ::core::option::Option<GradingPlatform>,
    #[prost(message, optional, tag = "6")]
    pub limits: ::core::option::Option<GradingLimits>,
    #[prost(message, repeated, tag = "7")]
    pub test_cases: ::prost::alloc::vec::Vec<TestCase>,
    /// named by ejudge checkers name
    #[prost(string, tag = "8")]
    pub standard_checker: ::prost::alloc::string::String,
    /// like ejudge checker environment
    #[prost(string, tag = "9")]
    pub standard_checker_opts: ::prost::alloc::string::String,
    /// checker source file
    #[prost(message, optional, tag = "10")]
    pub custom_checker: ::core::option::Option<File>,
    /// interactor source file
    #[prost(message, optional, tag = "11")]
    pub interactor: ::core::option::Option<File>,
    /// just copied from parent course for convince
    #[prost(message, repeated, tag = "12")]
    pub code_styles: ::prost::alloc::vec::Vec<CodeStyle>,
    #[prost(message, optional, tag = "13")]
    pub extra_build_files: ::core::option::Option<FileSet>,
    #[prost(message, optional, tag = "16")]
    pub tests_generator: ::core::option::Option<File>,
    /// supplementary program or script running the same unshare namespace
    #[prost(message, optional, tag = "17")]
    pub coprocess: ::core::option::Option<File>,
    #[prost(enumeration = "ExecutableTarget", tag = "20")]
    pub executable_target: i32,
    #[prost(enumeration = "BuildSystem", tag = "21")]
    pub build_system: i32,
    #[prost(map = "string, string", tag = "22")]
    pub build_properties: ::std::collections::HashMap<
        ::prost::alloc::string::String,
        ::prost::alloc::string::String,
    >,
    #[prost(map = "string, string", tag = "23")]
    pub target_properties: ::std::collections::HashMap<
        ::prost::alloc::string::String,
        ::prost::alloc::string::String,
    >,
    #[prost(message, optional, tag = "30")]
    pub security_context: ::core::option::Option<SecurityContext>,
    #[prost(bool, tag = "40")]
    pub tests_requires_build: bool,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct CodeStyle {
    #[prost(string, tag = "1")]
    pub source_file_suffix: ::prost::alloc::string::String,
    #[prost(message, optional, tag = "2")]
    pub style_file: ::core::option::Option<File>,
}
/// These data structures are not stored in database, but attached to courses via Problem records
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct ProblemData {
    /// string, but not int! id is a relative path to the problem directory
    #[prost(string, tag = "1")]
    pub id: ::prost::alloc::string::String,
    /// problem id to match previous years cheaters matching
    #[prost(string, tag = "2")]
    pub unique_id: ::prost::alloc::string::String,
    #[prost(string, tag = "3")]
    pub title: ::prost::alloc::string::String,
    #[prost(string, tag = "4")]
    pub statement_text: ::prost::alloc::string::String,
    /// text/markdown by default or text/html for legacy statements
    #[prost(string, tag = "5")]
    pub statement_content_type: ::prost::alloc::string::String,
    /// public files for students
    #[prost(message, optional, tag = "6")]
    pub statement_files: ::core::option::Option<FileSet>,
    /// fileset meta-information to be filled by solution
    #[prost(message, optional, tag = "7")]
    pub solution_files: ::core::option::Option<FileSet>,
    /// private files for grading
    #[prost(message, optional, tag = "8")]
    pub grader_files: ::core::option::Option<FileSet>,
    /// 1.0 by default, >1 for hard problems, <1 for easy problems
    #[prost(double, tag = "9")]
    pub full_score_multiplier_propose: f64,
    #[prost(message, optional, tag = "10")]
    pub grading_options: ::core::option::Option<GradingOptions>,
    /// This is problem property but not a problem usage in course/lesson property!
    /// Cons: the problem solution might be demonstrated sometime in past at another course
    #[prost(bool, tag = "11")]
    pub skip_plagiarism_check: bool,
    #[prost(int32, tag = "12")]
    pub max_submissions_per_hour: i32,
    #[prost(int32, tag = "13")]
    pub max_submission_file_size: i32,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct ProblemMetadata {
    /// matches problem data id
    #[prost(string, tag = "1")]
    pub id: ::prost::alloc::string::String,
    #[prost(double, tag = "2")]
    pub full_score_multiplier: f64,
    #[prost(bool, tag = "3")]
    pub blocks_next_problems: bool,
    #[prost(bool, tag = "4")]
    pub skip_solution_defence: bool,
    #[prost(bool, tag = "5")]
    pub skip_code_review: bool,
    #[prost(message, optional, tag = "10")]
    pub deadlines: ::core::option::Option<Deadlines>,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct ProblemStatus {
    #[prost(string, tag = "1")]
    pub problem_id: ::prost::alloc::string::String,
    #[prost(bool, tag = "2")]
    pub blocks_next: bool,
    #[prost(bool, tag = "3")]
    pub blocked_by_previous: bool,
    #[prost(bool, tag = "4")]
    pub completed: bool,
    #[prost(int32, tag = "5")]
    pub score_got: i32,
    #[prost(int32, tag = "6")]
    pub score_max: i32,
    /// real time
    #[prost(int64, tag = "7")]
    pub submitted: i64,
    #[prost(int32, tag = "10")]
    pub deadline_penalty_total: i32,
    #[prost(enumeration = "SolutionStatus", tag = "11")]
    pub final_solution_status: i32,
    #[prost(message, optional, tag = "12")]
    pub submission_count_limit: ::core::option::Option<SubmissionsCountLimit>,
    #[prost(message, repeated, tag = "13")]
    pub submissions: ::prost::alloc::vec::Vec<Submission>,
    #[prost(enumeration = "SubmissionProcessStatus", tag = "20")]
    pub final_grading_status: i32,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct LessonStatus {
    #[prost(string, tag = "1")]
    pub lesson_id: ::prost::alloc::string::String,
    #[prost(message, repeated, tag = "2")]
    pub problems: ::prost::alloc::vec::Vec<ProblemStatus>,
    #[prost(bool, tag = "3")]
    pub blocked_by_previous: bool,
    #[prost(bool, tag = "4")]
    pub blocks_next: bool,
    #[prost(bool, tag = "5")]
    pub completed: bool,
    #[prost(double, tag = "6")]
    pub score_got: f64,
    #[prost(double, tag = "7")]
    pub score_max: f64,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct SectionStatus {
    #[prost(string, tag = "1")]
    pub section_id: ::prost::alloc::string::String,
    #[prost(message, repeated, tag = "2")]
    pub lessons: ::prost::alloc::vec::Vec<LessonStatus>,
    #[prost(bool, tag = "3")]
    pub blocked_by_previous: bool,
    #[prost(bool, tag = "4")]
    pub blocks_next: bool,
    #[prost(bool, tag = "5")]
    pub completed: bool,
    #[prost(double, tag = "6")]
    pub score_got: f64,
    #[prost(double, tag = "7")]
    pub score_max: f64,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct CourseStatus {
    #[prost(message, optional, tag = "1")]
    pub course: ::core::option::Option<Course>,
    #[prost(message, optional, tag = "2")]
    pub user: ::core::option::Option<User>,
    #[prost(message, repeated, tag = "3")]
    pub sections: ::prost::alloc::vec::Vec<SectionStatus>,
    #[prost(int64, tag = "4")]
    pub hard_deadline: i64,
    #[prost(bool, tag = "5")]
    pub completed: bool,
    #[prost(double, tag = "6")]
    pub score_got: f64,
    #[prost(double, tag = "7")]
    pub score_max: f64,
    #[prost(int32, tag = "8")]
    pub problems_total: i32,
    #[prost(int32, tag = "9")]
    pub problems_required: i32,
    #[prost(int32, tag = "10")]
    pub problems_solved: i32,
    #[prost(int32, tag = "11")]
    pub problems_required_solved: i32,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct TestResult {
    #[prost(string, tag = "1")]
    pub target: ::prost::alloc::string::String,
    #[prost(enumeration = "SolutionStatus", tag = "2")]
    pub status: i32,
    #[prost(int32, tag = "3")]
    pub test_number: i32,
    #[prost(string, tag = "4")]
    pub stdout: ::prost::alloc::string::String,
    #[prost(string, tag = "5")]
    pub stderr: ::prost::alloc::string::String,
    #[prost(int32, tag = "6")]
    pub exit_status: i32,
    #[prost(int32, tag = "7")]
    pub signal_killed: i32,
    #[prost(bool, tag = "8")]
    pub standard_match: bool,
    #[prost(bool, tag = "9")]
    pub killed_by_timer: bool,
    #[prost(string, tag = "10")]
    pub valgrind_output: ::prost::alloc::string::String,
    #[prost(int32, tag = "11")]
    pub valgrind_errors: i32,
    #[prost(string, tag = "12")]
    pub checker_output: ::prost::alloc::string::String,
    /// if test has custom build files
    #[prost(string, tag = "13")]
    pub build_error_log: ::prost::alloc::string::String,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct Submission {
    #[prost(int64, tag = "1")]
    pub id: i64,
    #[prost(message, optional, tag = "2")]
    pub user: ::core::option::Option<User>,
    #[prost(message, optional, tag = "3")]
    pub course: ::core::option::Option<Course>,
    /// seconds since epoch UTC
    #[prost(int64, tag = "4")]
    pub datetime: i64,
    #[prost(message, optional, tag = "5")]
    pub solution_files: ::core::option::Option<FileSet>,
    #[prost(enumeration = "SolutionStatus", tag = "6")]
    pub status: i32,
    #[prost(double, tag = "7")]
    pub grader_score: f64,
    /// id of grader that processed submission
    #[prost(string, tag = "8")]
    pub grader_name: ::prost::alloc::string::String,
    #[prost(string, tag = "9")]
    pub style_error_log: ::prost::alloc::string::String,
    #[prost(string, tag = "10")]
    pub build_error_log: ::prost::alloc::string::String,
    #[prost(message, optional, tag = "11")]
    pub code_review: ::core::option::Option<CodeReview>,
    #[prost(string, tag = "12")]
    pub problem_id: ::prost::alloc::string::String,
    #[prost(message, repeated, tag = "13")]
    pub test_results: ::prost::alloc::vec::Vec<TestResult>,
    /// Cheat detection
    #[prost(double, tag = "20")]
    pub maximum_similarity_found: f64,
    #[prost(enumeration = "SubmissionProcessStatus", tag = "100")]
    pub grading_status: i32,
    #[prost(enumeration = "SubmissionProcessStatus", tag = "101")]
    pub cheat_check_status: i32,
    /// timestamp to be used for repeat sending in case of error
    #[prost(int64, tag = "201")]
    pub sent_to_grader: i64,
    /// not to be stored directly in database
    #[prost(int64, tag = "300")]
    pub soft_deadline: i64,
    #[prost(int64, tag = "301")]
    pub hard_deadline: i64,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct Solution {
    #[prost(int64, tag = "1")]
    pub id: i64,
    /// must contain at least Problem.id
    #[prost(message, optional, tag = "2")]
    pub problem: ::core::option::Option<ProblemData>,
    #[prost(message, repeated, tag = "3")]
    pub history: ::prost::alloc::vec::Vec<Submission>,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct Deadlines {
    /// all durations are in seconds
    #[prost(int32, tag = "1")]
    pub soft_deadline: i32,
    #[prost(int32, tag = "2")]
    pub hard_deadline: i32,
    #[prost(int32, tag = "3")]
    pub soft_penalty: i32,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct LessonSchedule {
    /// seconds from epoch (UTC)
    #[prost(int64, tag = "1")]
    pub datetime: i64,
    /// the fields below are in use for database storage but should be expanded into plain schedule entries
    #[prost(int32, tag = "10")]
    pub repeat_count: i32,
    /// in seconds
    #[prost(int32, tag = "11")]
    pub repeat_interval: i32,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct LessonScheduleSet {
    /// lesson full id (delimited by '/' and normalized) ---> seconds from epoch (UTC)
    #[prost(map = "string, int64", tag = "1")]
    pub schedules: ::std::collections::HashMap<::prost::alloc::string::String, i64>,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct Lesson {
    #[prost(string, tag = "1")]
    pub id: ::prost::alloc::string::String,
    #[prost(string, tag = "3")]
    pub name: ::prost::alloc::string::String,
    #[prost(string, tag = "4")]
    pub description: ::prost::alloc::string::String,
    #[prost(message, repeated, tag = "5")]
    pub readings: ::prost::alloc::vec::Vec<TextReading>,
    #[prost(message, repeated, tag = "6")]
    pub problems: ::prost::alloc::vec::Vec<ProblemData>,
    #[prost(message, repeated, tag = "7")]
    pub problems_metadata: ::prost::alloc::vec::Vec<ProblemMetadata>,
    #[prost(message, optional, tag = "10")]
    pub deadlines: ::core::option::Option<Deadlines>,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct Section {
    #[prost(string, tag = "1")]
    pub id: ::prost::alloc::string::String,
    #[prost(string, tag = "2")]
    pub name: ::prost::alloc::string::String,
    #[prost(string, tag = "3")]
    pub description: ::prost::alloc::string::String,
    #[prost(message, repeated, tag = "4")]
    pub lessons: ::prost::alloc::vec::Vec<Lesson>,
    #[prost(message, optional, tag = "10")]
    pub deadlines: ::core::option::Option<Deadlines>,
}
/// Courses are stored in filesystem directories but not in database.
/// ID is a string path after the courses root directory.
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct CourseData {
    #[prost(string, tag = "1")]
    pub id: ::prost::alloc::string::String,
    #[prost(string, tag = "2")]
    pub description: ::prost::alloc::string::String,
    #[prost(message, repeated, tag = "3")]
    pub sections: ::prost::alloc::vec::Vec<Section>,
    #[prost(int32, tag = "4")]
    pub max_submissions_per_hour: i32,
    #[prost(int32, tag = "5")]
    pub max_submission_file_size: i32,
    #[prost(message, repeated, tag = "6")]
    pub code_styles: ::prost::alloc::vec::Vec<CodeStyle>,
    #[prost(message, optional, tag = "7")]
    pub default_limits: ::core::option::Option<GradingLimits>,
    #[prost(message, optional, tag = "10")]
    pub deadlines: ::core::option::Option<Deadlines>,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct Course {
    #[prost(int32, tag = "1")]
    pub id: i32,
    #[prost(string, tag = "2")]
    pub name: ::prost::alloc::string::String,
    #[prost(string, tag = "3")]
    pub data_id: ::prost::alloc::string::String,
    #[prost(string, tag = "5")]
    pub url_prefix: ::prost::alloc::string::String,
    #[prost(bool, tag = "7")]
    pub disable_review: bool,
    #[prost(bool, tag = "8")]
    pub disable_defence: bool,
    #[prost(string, tag = "9")]
    pub description: ::prost::alloc::string::String,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct Enrollment {
    #[prost(message, optional, tag = "1")]
    pub course: ::core::option::Option<Course>,
    #[prost(message, optional, tag = "2")]
    pub user: ::core::option::Option<User>,
    #[prost(enumeration = "Role", tag = "3")]
    pub role: i32,
    #[prost(string, tag = "4")]
    pub group_pattern: ::prost::alloc::string::String,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct UserRole {
    #[prost(message, optional, tag = "1")]
    pub user: ::core::option::Option<User>,
    #[prost(enumeration = "Role", tag = "2")]
    pub role: i32,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct CoursesFilter {
    /// courses available to specified user, no filter in case of User.id==0
    #[prost(message, optional, tag = "1")]
    pub user: ::core::option::Option<User>,
    /// filter by name, no filter in case of Course.id==0
    #[prost(message, optional, tag = "2")]
    pub course: ::core::option::Option<Course>,
    #[prost(bool, tag = "3")]
    pub partial_string_match: bool,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct CoursesList {
    #[prost(message, repeated, tag = "1")]
    pub courses: ::prost::alloc::vec::Vec<courses_list::CourseListEntry>,
}
/// Nested message and enum types in `CoursesList`.
pub mod courses_list {
    #[allow(clippy::derive_partial_eq_without_eq)]
    #[derive(Clone, PartialEq, ::prost::Message)]
    pub struct CourseListEntry {
        #[prost(message, optional, tag = "1")]
        pub course: ::core::option::Option<super::Course>,
        #[prost(enumeration = "super::Role", tag = "2")]
        pub role: i32,
    }
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct CourseContentRequest {
    #[prost(string, tag = "1")]
    pub course_data_id: ::prost::alloc::string::String,
    #[prost(int64, tag = "2")]
    pub cached_timestamp: i64,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct ProblemContentRequest {
    #[prost(string, tag = "1")]
    pub course_data_id: ::prost::alloc::string::String,
    #[prost(string, tag = "2")]
    pub problem_id: ::prost::alloc::string::String,
    #[prost(int64, tag = "3")]
    pub cached_timestamp: i64,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct ProblemContentResponse {
    #[prost(string, tag = "1")]
    pub course_data_id: ::prost::alloc::string::String,
    #[prost(string, tag = "2")]
    pub problem_id: ::prost::alloc::string::String,
    #[prost(int64, tag = "3")]
    pub last_modified: i64,
    #[prost(enumeration = "ContentStatus", tag = "4")]
    pub status: i32,
    #[prost(message, optional, tag = "5")]
    pub data: ::core::option::Option<ProblemData>,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct CourseContentResponse {
    #[prost(string, tag = "1")]
    pub course_data_id: ::prost::alloc::string::String,
    #[prost(enumeration = "ContentStatus", tag = "2")]
    pub status: i32,
    #[prost(message, optional, tag = "3")]
    pub data: ::core::option::Option<CourseData>,
    #[prost(int64, tag = "4")]
    pub last_modified: i64,
}
/// message sent when user have read (scrolled) text reading
/// to mark reading 'passed' and estimate average reading time
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct TextReadingDone {
    /// id only important
    #[prost(message, optional, tag = "1")]
    pub user: ::core::option::Option<User>,
    /// id only important
    #[prost(message, optional, tag = "2")]
    pub course: ::core::option::Option<Course>,
    /// id only important
    #[prost(message, optional, tag = "3")]
    pub section: ::core::option::Option<Section>,
    /// id only important
    #[prost(message, optional, tag = "4")]
    pub lesson: ::core::option::Option<Lesson>,
    /// id only important
    #[prost(message, optional, tag = "5")]
    pub reading: ::core::option::Option<TextReading>,
    /// in seconds from page load to leave
    #[prost(int64, tag = "6")]
    pub time: i64,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct CourseProgressRequest {
    #[prost(message, optional, tag = "1")]
    pub course: ::core::option::Option<Course>,
    #[prost(string, tag = "2")]
    pub name_filter: ::prost::alloc::string::String,
    #[prost(bool, tag = "3")]
    pub include_problem_details: bool,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct CourseStatusEntry {
    #[prost(message, optional, tag = "1")]
    pub user: ::core::option::Option<User>,
    #[prost(message, repeated, tag = "2")]
    pub statuses: ::prost::alloc::vec::Vec<ProblemStatus>,
    #[prost(double, repeated, tag = "3")]
    pub scores: ::prost::alloc::vec::Vec<f64>,
    #[prost(bool, tag = "4")]
    pub course_completed: bool,
    #[prost(double, tag = "5")]
    pub score_got: f64,
    #[prost(double, tag = "6")]
    pub score_max: f64,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct CourseProgressResponse {
    #[prost(message, repeated, tag = "1")]
    pub entries: ::prost::alloc::vec::Vec<CourseStatusEntry>,
    #[prost(message, repeated, tag = "2")]
    pub problems: ::prost::alloc::vec::Vec<ProblemData>,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct LessonScheduleRequest {
    #[prost(message, optional, tag = "1")]
    pub course: ::core::option::Option<Course>,
    #[prost(message, optional, tag = "2")]
    pub user: ::core::option::Option<User>,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct EnrollUserRequest {
    #[prost(message, optional, tag = "1")]
    pub course: ::core::option::Option<Course>,
    #[prost(message, optional, tag = "2")]
    pub user: ::core::option::Option<User>,
    #[prost(enumeration = "Role", tag = "3")]
    pub role: i32,
    #[prost(string, tag = "4")]
    pub group_pattern: ::prost::alloc::string::String,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct EnrollGroupRequest {
    #[prost(message, optional, tag = "1")]
    pub course: ::core::option::Option<Course>,
    #[prost(string, tag = "2")]
    pub group_pattern: ::prost::alloc::string::String,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct GroupEnrollmentsRequest {
    #[prost(message, optional, tag = "1")]
    pub course: ::core::option::Option<Course>,
    #[prost(string, tag = "2")]
    pub group_pattern: ::prost::alloc::string::String,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct GroupEnrollments {
    #[prost(int32, tag = "1")]
    pub id: i32,
    #[prost(string, tag = "2")]
    pub group_pattern: ::prost::alloc::string::String,
    #[prost(message, repeated, tag = "3")]
    pub group_students: ::prost::alloc::vec::Vec<User>,
    #[prost(message, repeated, tag = "4")]
    pub foreign_students: ::prost::alloc::vec::Vec<User>,
    #[prost(message, repeated, tag = "5")]
    pub teachers: ::prost::alloc::vec::Vec<User>,
    #[prost(message, repeated, tag = "6")]
    pub assistants: ::prost::alloc::vec::Vec<User>,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct AllGroupsEnrollments {
    #[prost(message, optional, tag = "1")]
    pub course: ::core::option::Option<Course>,
    #[prost(message, repeated, tag = "2")]
    pub groups: ::prost::alloc::vec::Vec<GroupEnrollments>,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct UserEnrollments {
    #[prost(message, repeated, tag = "1")]
    pub enrollments: ::prost::alloc::vec::Vec<Enrollment>,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct ConnectedServiceProperties {
    #[prost(string, tag = "1")]
    pub name: ::prost::alloc::string::String,
    #[prost(message, optional, tag = "2")]
    pub platform: ::core::option::Option<GradingPlatform>,
    /// higher is better: 1_000_000/(time_in_ms_for_20000_primes_generation)
    #[prost(double, tag = "3")]
    pub performance_rating: f64,
    #[prost(bool, tag = "4")]
    pub arch_specific_only_jobs: bool,
    /// number of CPU cores available to grade in parallel
    #[prost(int32, tag = "5")]
    pub number_of_workers: i32,
    #[prost(enumeration = "ServiceRole", tag = "10")]
    pub role: i32,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct SubmissionsCountLimit {
    #[prost(int32, tag = "1")]
    pub attempts_left: i32,
    #[prost(int64, tag = "2")]
    pub next_time_reset: i64,
    #[prost(int64, tag = "3")]
    pub server_time: i64,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct SubmissionList {
    #[prost(message, repeated, tag = "1")]
    pub submissions: ::prost::alloc::vec::Vec<Submission>,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct SubmissionFilter {
    #[prost(message, optional, tag = "1")]
    pub user: ::core::option::Option<User>,
    #[prost(message, optional, tag = "2")]
    pub course: ::core::option::Option<Course>,
    #[prost(string, tag = "3")]
    pub problem_id: ::prost::alloc::string::String,
    #[prost(enumeration = "SolutionStatus", tag = "4")]
    pub status: i32,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct CheckCourseStatusRequest {
    #[prost(message, optional, tag = "1")]
    pub user: ::core::option::Option<User>,
    #[prost(message, optional, tag = "2")]
    pub course: ::core::option::Option<Course>,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct ProblemStatusRequest {
    #[prost(message, optional, tag = "1")]
    pub user: ::core::option::Option<User>,
    #[prost(message, optional, tag = "2")]
    pub course: ::core::option::Option<Course>,
    #[prost(string, tag = "3")]
    pub problem_id: ::prost::alloc::string::String,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct RejudgeRequest {
    #[prost(message, optional, tag = "1")]
    pub user: ::core::option::Option<User>,
    #[prost(message, optional, tag = "2")]
    pub course: ::core::option::Option<Course>,
    #[prost(string, tag = "3")]
    pub problem_id: ::prost::alloc::string::String,
    #[prost(message, optional, tag = "4")]
    pub submission: ::core::option::Option<Submission>,
    #[prost(bool, tag = "5")]
    pub only_failed_submissions: bool,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct LocalGraderSubmission {
    #[prost(message, optional, tag = "1")]
    pub submission: ::core::option::Option<Submission>,
    #[prost(message, optional, tag = "2")]
    pub grading_limits: ::core::option::Option<GradingLimits>,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct SubmissionListQuery {
    /// ignore rest fields if > 0
    #[prost(int64, tag = "1")]
    pub submission_id: i64,
    #[prost(int32, tag = "2")]
    pub course_id: i32,
    #[prost(string, tag = "3")]
    pub name_query: ::prost::alloc::string::String,
    #[prost(string, tag = "4")]
    pub problem_id_filter: ::prost::alloc::string::String,
    #[prost(enumeration = "SolutionStatus", tag = "5")]
    pub status_filter: i32,
    #[prost(bool, tag = "6")]
    pub show_mine_submissions: bool,
    #[prost(int32, tag = "20")]
    pub limit: i32,
    #[prost(int32, tag = "21")]
    pub offset: i32,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct SubmissionListNotificationsRequest {
    #[prost(message, optional, tag = "1")]
    pub filter_request: ::core::option::Option<SubmissionListQuery>,
    #[prost(int64, repeated, tag = "2")]
    pub submission_ids: ::prost::alloc::vec::Vec<i64>,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct SubmissionListEntry {
    #[prost(int64, tag = "1")]
    pub submission_id: i64,
    #[prost(enumeration = "SolutionStatus", tag = "2")]
    pub status: i32,
    #[prost(message, optional, tag = "3")]
    pub sender: ::core::option::Option<User>,
    #[prost(int64, tag = "4")]
    pub datetime: i64,
    #[prost(string, tag = "5")]
    pub problem_id: ::prost::alloc::string::String,
    #[prost(bool, tag = "6")]
    pub hard_deadline_passed: bool,
    #[prost(enumeration = "SubmissionProcessStatus", tag = "10")]
    pub grading_status: i32,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct SubmissionListResponse {
    #[prost(message, repeated, tag = "1")]
    pub entries: ::prost::alloc::vec::Vec<SubmissionListEntry>,
    #[prost(int32, tag = "2")]
    pub total_count: i32,
    #[prost(message, optional, tag = "3")]
    pub query: ::core::option::Option<SubmissionListQuery>,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct Empty {}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct ConnectedServiceStatus {
    #[prost(message, optional, tag = "1")]
    pub properties: ::core::option::Option<ConnectedServiceProperties>,
    #[prost(enumeration = "ServiceStatus", tag = "2")]
    pub status: i32,
    #[prost(int32, tag = "3")]
    pub capacity: i32,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct SolutionExternalSource {
    #[prost(int64, tag = "1")]
    pub id: i64,
    #[prost(string, tag = "2")]
    pub known_url: ::prost::alloc::string::String,
    #[prost(string, tag = "3")]
    pub known_author: ::prost::alloc::string::String,
    #[prost(string, tag = "4")]
    pub problem_id: ::prost::alloc::string::String,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct SolutionSource {
    #[prost(oneof = "solution_source::What", tags = "1, 2")]
    pub what: ::core::option::Option<solution_source::What>,
}
/// Nested message and enum types in `SolutionSource`.
pub mod solution_source {
    #[allow(clippy::derive_partial_eq_without_eq)]
    #[derive(Clone, PartialEq, ::prost::Oneof)]
    pub enum What {
        #[prost(message, tag = "1")]
        Submission(super::Submission),
        #[prost(message, tag = "2")]
        External(super::SolutionExternalSource),
    }
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct SolutionData {
    #[prost(message, optional, tag = "1")]
    pub file_set: ::core::option::Option<FileSet>,
    #[prost(message, optional, tag = "2")]
    pub source: ::core::option::Option<SolutionSource>,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct DiffViewRequest {
    #[prost(message, optional, tag = "1")]
    pub first: ::core::option::Option<SolutionSource>,
    #[prost(message, optional, tag = "2")]
    pub second: ::core::option::Option<SolutionSource>,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct LineRange {
    #[prost(int32, tag = "1")]
    pub start: i32,
    #[prost(int32, tag = "2")]
    pub end: i32,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct DiffOperation {
    #[prost(message, optional, tag = "1")]
    pub from: ::core::option::Option<LineRange>,
    #[prost(message, optional, tag = "2")]
    pub to: ::core::option::Option<LineRange>,
    #[prost(enumeration = "DiffOperationType", tag = "3")]
    pub operation: i32,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct DiffData {
    #[prost(string, tag = "1")]
    pub file_name: ::prost::alloc::string::String,
    #[prost(string, tag = "2")]
    pub first_text: ::prost::alloc::string::String,
    #[prost(string, tag = "3")]
    pub second_text: ::prost::alloc::string::String,
    #[prost(message, repeated, tag = "4")]
    pub operations: ::prost::alloc::vec::Vec<DiffOperation>,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct DiffViewResponse {
    #[prost(message, repeated, tag = "1")]
    pub diffs: ::prost::alloc::vec::Vec<DiffData>,
    #[prost(message, optional, tag = "2")]
    pub request: ::core::option::Option<DiffViewRequest>,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct LineComment {
    /// starting from 0
    #[prost(int32, tag = "1")]
    pub line_number: i32,
    /// short line text to be shown in history
    #[prost(string, tag = "2")]
    pub context: ::prost::alloc::string::String,
    #[prost(string, tag = "3")]
    pub message: ::prost::alloc::string::String,
    #[prost(string, tag = "4")]
    pub file_name: ::prost::alloc::string::String,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct CodeReview {
    #[prost(int64, tag = "1")]
    pub id: i64,
    /// seconds from epoch UTC
    #[prost(int64, tag = "2")]
    pub datetime: i64,
    #[prost(int64, tag = "3")]
    pub submission_id: i64,
    #[prost(message, optional, tag = "4")]
    pub author: ::core::option::Option<User>,
    #[prost(message, repeated, tag = "5")]
    pub line_comments: ::prost::alloc::vec::Vec<LineComment>,
    #[prost(string, tag = "6")]
    pub global_comment: ::prost::alloc::string::String,
    #[prost(enumeration = "SolutionStatus", tag = "7")]
    pub new_status: i32,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct ReviewHistory {
    #[prost(message, repeated, tag = "1")]
    pub reviews: ::prost::alloc::vec::Vec<CodeReview>,
}
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct CourseEntryPoint {
    #[prost(string, tag = "1")]
    pub url_prefix: ::prost::alloc::string::String,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, ::prost::Enumeration)]
#[repr(i32)]
pub enum Role {
    Any = 0,
    Unauthorized = 1,
    Student = 2,
    TeacherAssistant = 3,
    Teacher = 4,
    Lecturer = 5,
    Administrator = 6,
}
impl Role {
    /// String value of the enum field names used in the ProtoBuf definition.
    ///
    /// The values are not transformed in any way and thus are considered stable
    /// (if the ProtoBuf definition does not change) and safe for programmatic use.
    pub fn as_str_name(&self) -> &'static str {
        match self {
            Role::Any => "ROLE_ANY",
            Role::Unauthorized => "ROLE_UNAUTHORIZED",
            Role::Student => "ROLE_STUDENT",
            Role::TeacherAssistant => "ROLE_TEACHER_ASSISTANT",
            Role::Teacher => "ROLE_TEACHER",
            Role::Lecturer => "ROLE_LECTURER",
            Role::Administrator => "ROLE_ADMINISTRATOR",
        }
    }
    /// Creates an enum from field names used in the ProtoBuf definition.
    pub fn from_str_name(value: &str) -> ::core::option::Option<Self> {
        match value {
            "ROLE_ANY" => Some(Self::Any),
            "ROLE_UNAUTHORIZED" => Some(Self::Unauthorized),
            "ROLE_STUDENT" => Some(Self::Student),
            "ROLE_TEACHER_ASSISTANT" => Some(Self::TeacherAssistant),
            "ROLE_TEACHER" => Some(Self::Teacher),
            "ROLE_LECTURER" => Some(Self::Lecturer),
            "ROLE_ADMINISTRATOR" => Some(Self::Administrator),
            _ => None,
        }
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, ::prost::Enumeration)]
#[repr(i32)]
pub enum Arch {
    Any = 0,
    X86 = 1,
    X8664 = 2,
    Armv7 = 3,
    Aarch64 = 4,
}
impl Arch {
    /// String value of the enum field names used in the ProtoBuf definition.
    ///
    /// The values are not transformed in any way and thus are considered stable
    /// (if the ProtoBuf definition does not change) and safe for programmatic use.
    pub fn as_str_name(&self) -> &'static str {
        match self {
            Arch::Any => "ARCH_ANY",
            Arch::X86 => "ARCH_X86",
            Arch::X8664 => "ARCH_X86_64",
            Arch::Armv7 => "ARCH_ARMV7",
            Arch::Aarch64 => "ARCH_AARCH64",
        }
    }
    /// Creates an enum from field names used in the ProtoBuf definition.
    pub fn from_str_name(value: &str) -> ::core::option::Option<Self> {
        match value {
            "ARCH_ANY" => Some(Self::Any),
            "ARCH_X86" => Some(Self::X86),
            "ARCH_X86_64" => Some(Self::X8664),
            "ARCH_ARMV7" => Some(Self::Armv7),
            "ARCH_AARCH64" => Some(Self::Aarch64),
            _ => None,
        }
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, ::prost::Enumeration)]
#[repr(i32)]
pub enum ExecutableTarget {
    AutodetectExecutable = 0,
    /// text scripts
    ShellScript = 1,
    PythonScript = 2,
    /// native executables
    Native = 10,
    NativeWithSanitizers = 11,
    NativeWithValgrind = 12,
    /// expands to two targets: sanitizers and valgrind
    NativeWithSanitizersAndValgrind = 13,
    /// jre code
    JavaClass = 21,
    JavaJar = 22,
    /// QEMU disk images
    QemuSystemImage = 31,
}
impl ExecutableTarget {
    /// String value of the enum field names used in the ProtoBuf definition.
    ///
    /// The values are not transformed in any way and thus are considered stable
    /// (if the ProtoBuf definition does not change) and safe for programmatic use.
    pub fn as_str_name(&self) -> &'static str {
        match self {
            ExecutableTarget::AutodetectExecutable => "AutodetectExecutable",
            ExecutableTarget::ShellScript => "ShellScript",
            ExecutableTarget::PythonScript => "PythonScript",
            ExecutableTarget::Native => "Native",
            ExecutableTarget::NativeWithSanitizers => "NativeWithSanitizers",
            ExecutableTarget::NativeWithValgrind => "NativeWithValgrind",
            ExecutableTarget::NativeWithSanitizersAndValgrind => {
                "NativeWithSanitizersAndValgrind"
            }
            ExecutableTarget::JavaClass => "JavaClass",
            ExecutableTarget::JavaJar => "JavaJar",
            ExecutableTarget::QemuSystemImage => "QemuSystemImage",
        }
    }
    /// Creates an enum from field names used in the ProtoBuf definition.
    pub fn from_str_name(value: &str) -> ::core::option::Option<Self> {
        match value {
            "AutodetectExecutable" => Some(Self::AutodetectExecutable),
            "ShellScript" => Some(Self::ShellScript),
            "PythonScript" => Some(Self::PythonScript),
            "Native" => Some(Self::Native),
            "NativeWithSanitizers" => Some(Self::NativeWithSanitizers),
            "NativeWithValgrind" => Some(Self::NativeWithValgrind),
            "NativeWithSanitizersAndValgrind" => {
                Some(Self::NativeWithSanitizersAndValgrind)
            }
            "JavaClass" => Some(Self::JavaClass),
            "JavaJar" => Some(Self::JavaJar),
            "QemuSystemImage" => Some(Self::QemuSystemImage),
            _ => None,
        }
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, ::prost::Enumeration)]
#[repr(i32)]
pub enum BuildSystem {
    AutodetectBuild = 0,
    SkipBuild = 1,
    /// Python language
    PythonCheckers = 10,
    /// C, C++, ASM
    ClangToolchain = 20,
    /// custom projects
    MakefileProject = 30,
    /// custom projects
    CMakeProject = 40,
    /// Go
    GoLangProject = 50,
    /// Java
    JavaPlainProject = 60,
    /// maven using pom.xml
    MavenProject = 61,
}
impl BuildSystem {
    /// String value of the enum field names used in the ProtoBuf definition.
    ///
    /// The values are not transformed in any way and thus are considered stable
    /// (if the ProtoBuf definition does not change) and safe for programmatic use.
    pub fn as_str_name(&self) -> &'static str {
        match self {
            BuildSystem::AutodetectBuild => "AutodetectBuild",
            BuildSystem::SkipBuild => "SkipBuild",
            BuildSystem::PythonCheckers => "PythonCheckers",
            BuildSystem::ClangToolchain => "ClangToolchain",
            BuildSystem::MakefileProject => "MakefileProject",
            BuildSystem::CMakeProject => "CMakeProject",
            BuildSystem::GoLangProject => "GoLangProject",
            BuildSystem::JavaPlainProject => "JavaPlainProject",
            BuildSystem::MavenProject => "MavenProject",
        }
    }
    /// Creates an enum from field names used in the ProtoBuf definition.
    pub fn from_str_name(value: &str) -> ::core::option::Option<Self> {
        match value {
            "AutodetectBuild" => Some(Self::AutodetectBuild),
            "SkipBuild" => Some(Self::SkipBuild),
            "PythonCheckers" => Some(Self::PythonCheckers),
            "ClangToolchain" => Some(Self::ClangToolchain),
            "MakefileProject" => Some(Self::MakefileProject),
            "CMakeProject" => Some(Self::CMakeProject),
            "GoLangProject" => Some(Self::GoLangProject),
            "JavaPlainProject" => Some(Self::JavaPlainProject),
            "MavenProject" => Some(Self::MavenProject),
            _ => None,
        }
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, ::prost::Enumeration)]
#[repr(i32)]
pub enum SolutionStatus {
    AnyStatusOrNull = 0,
    StyleCheckError = 3,
    CompilationError = 4,
    WrongAnswer = 5,
    SummonForDefence = 6,
    PendingReview = 7,
    CodeReviewRejected = 8,
    Disqualified = 12,
    CheckFailed = 13,
    RuntimeError = 14,
    TimeLimit = 15,
    ValgrindErrors = 16,
    Ok = 100,
    /// Values from 300 are possible at UI usage only and should not appear in database!
    HardDeadlinePassed = 300,
}
impl SolutionStatus {
    /// String value of the enum field names used in the ProtoBuf definition.
    ///
    /// The values are not transformed in any way and thus are considered stable
    /// (if the ProtoBuf definition does not change) and safe for programmatic use.
    pub fn as_str_name(&self) -> &'static str {
        match self {
            SolutionStatus::AnyStatusOrNull => "ANY_STATUS_OR_NULL",
            SolutionStatus::StyleCheckError => "STYLE_CHECK_ERROR",
            SolutionStatus::CompilationError => "COMPILATION_ERROR",
            SolutionStatus::WrongAnswer => "WRONG_ANSWER",
            SolutionStatus::SummonForDefence => "SUMMON_FOR_DEFENCE",
            SolutionStatus::PendingReview => "PENDING_REVIEW",
            SolutionStatus::CodeReviewRejected => "CODE_REVIEW_REJECTED",
            SolutionStatus::Disqualified => "DISQUALIFIED",
            SolutionStatus::CheckFailed => "CHECK_FAILED",
            SolutionStatus::RuntimeError => "RUNTIME_ERROR",
            SolutionStatus::TimeLimit => "TIME_LIMIT",
            SolutionStatus::ValgrindErrors => "VALGRIND_ERRORS",
            SolutionStatus::Ok => "OK",
            SolutionStatus::HardDeadlinePassed => "HARD_DEADLINE_PASSED",
        }
    }
    /// Creates an enum from field names used in the ProtoBuf definition.
    pub fn from_str_name(value: &str) -> ::core::option::Option<Self> {
        match value {
            "ANY_STATUS_OR_NULL" => Some(Self::AnyStatusOrNull),
            "STYLE_CHECK_ERROR" => Some(Self::StyleCheckError),
            "COMPILATION_ERROR" => Some(Self::CompilationError),
            "WRONG_ANSWER" => Some(Self::WrongAnswer),
            "SUMMON_FOR_DEFENCE" => Some(Self::SummonForDefence),
            "PENDING_REVIEW" => Some(Self::PendingReview),
            "CODE_REVIEW_REJECTED" => Some(Self::CodeReviewRejected),
            "DISQUALIFIED" => Some(Self::Disqualified),
            "CHECK_FAILED" => Some(Self::CheckFailed),
            "RUNTIME_ERROR" => Some(Self::RuntimeError),
            "TIME_LIMIT" => Some(Self::TimeLimit),
            "VALGRIND_ERRORS" => Some(Self::ValgrindErrors),
            "OK" => Some(Self::Ok),
            "HARD_DEADLINE_PASSED" => Some(Self::HardDeadlinePassed),
            _ => None,
        }
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, ::prost::Enumeration)]
#[repr(i32)]
pub enum SubmissionProcessStatus {
    ProcessQueued = 0,
    ProcessAssigned = 1,
    ProcessDone = 2,
}
impl SubmissionProcessStatus {
    /// String value of the enum field names used in the ProtoBuf definition.
    ///
    /// The values are not transformed in any way and thus are considered stable
    /// (if the ProtoBuf definition does not change) and safe for programmatic use.
    pub fn as_str_name(&self) -> &'static str {
        match self {
            SubmissionProcessStatus::ProcessQueued => "PROCESS_QUEUED",
            SubmissionProcessStatus::ProcessAssigned => "PROCESS_ASSIGNED",
            SubmissionProcessStatus::ProcessDone => "PROCESS_DONE",
        }
    }
    /// Creates an enum from field names used in the ProtoBuf definition.
    pub fn from_str_name(value: &str) -> ::core::option::Option<Self> {
        match value {
            "PROCESS_QUEUED" => Some(Self::ProcessQueued),
            "PROCESS_ASSIGNED" => Some(Self::ProcessAssigned),
            "PROCESS_DONE" => Some(Self::ProcessDone),
            _ => None,
        }
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, ::prost::Enumeration)]
#[repr(i32)]
pub enum ContentStatus {
    HasData = 0,
    NotChanged = 1,
}
impl ContentStatus {
    /// String value of the enum field names used in the ProtoBuf definition.
    ///
    /// The values are not transformed in any way and thus are considered stable
    /// (if the ProtoBuf definition does not change) and safe for programmatic use.
    pub fn as_str_name(&self) -> &'static str {
        match self {
            ContentStatus::HasData => "HAS_DATA",
            ContentStatus::NotChanged => "NOT_CHANGED",
        }
    }
    /// Creates an enum from field names used in the ProtoBuf definition.
    pub fn from_str_name(value: &str) -> ::core::option::Option<Self> {
        match value {
            "HAS_DATA" => Some(Self::HasData),
            "NOT_CHANGED" => Some(Self::NotChanged),
            _ => None,
        }
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, ::prost::Enumeration)]
#[repr(i32)]
pub enum ServiceRole {
    ServiceGrading = 0,
    ServiceCheatChecking = 1,
}
impl ServiceRole {
    /// String value of the enum field names used in the ProtoBuf definition.
    ///
    /// The values are not transformed in any way and thus are considered stable
    /// (if the ProtoBuf definition does not change) and safe for programmatic use.
    pub fn as_str_name(&self) -> &'static str {
        match self {
            ServiceRole::ServiceGrading => "SERVICE_GRADING",
            ServiceRole::ServiceCheatChecking => "SERVICE_CHEAT_CHECKING",
        }
    }
    /// Creates an enum from field names used in the ProtoBuf definition.
    pub fn from_str_name(value: &str) -> ::core::option::Option<Self> {
        match value {
            "SERVICE_GRADING" => Some(Self::ServiceGrading),
            "SERVICE_CHEAT_CHECKING" => Some(Self::ServiceCheatChecking),
            _ => None,
        }
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, ::prost::Enumeration)]
#[repr(i32)]
pub enum ServiceStatus {
    Unknown = 0,
    Idle = 1,
    Busy = 2,
    ShuttingDown = 3,
}
impl ServiceStatus {
    /// String value of the enum field names used in the ProtoBuf definition.
    ///
    /// The values are not transformed in any way and thus are considered stable
    /// (if the ProtoBuf definition does not change) and safe for programmatic use.
    pub fn as_str_name(&self) -> &'static str {
        match self {
            ServiceStatus::Unknown => "SERVICE_STATUS_UNKNOWN",
            ServiceStatus::Idle => "SERVICE_STATUS_IDLE",
            ServiceStatus::Busy => "SERVICE_STATUS_BUSY",
            ServiceStatus::ShuttingDown => "SERVICE_STATUS_SHUTTING_DOWN",
        }
    }
    /// Creates an enum from field names used in the ProtoBuf definition.
    pub fn from_str_name(value: &str) -> ::core::option::Option<Self> {
        match value {
            "SERVICE_STATUS_UNKNOWN" => Some(Self::Unknown),
            "SERVICE_STATUS_IDLE" => Some(Self::Idle),
            "SERVICE_STATUS_BUSY" => Some(Self::Busy),
            "SERVICE_STATUS_SHUTTING_DOWN" => Some(Self::ShuttingDown),
            _ => None,
        }
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, ::prost::Enumeration)]
#[repr(i32)]
pub enum DiffOperationType {
    LineEqual = 0,
    LineDiffer = 1,
    LineDeleted = 2,
    LineInserted = 3,
}
impl DiffOperationType {
    /// String value of the enum field names used in the ProtoBuf definition.
    ///
    /// The values are not transformed in any way and thus are considered stable
    /// (if the ProtoBuf definition does not change) and safe for programmatic use.
    pub fn as_str_name(&self) -> &'static str {
        match self {
            DiffOperationType::LineEqual => "LINE_EQUAL",
            DiffOperationType::LineDiffer => "LINE_DIFFER",
            DiffOperationType::LineDeleted => "LINE_DELETED",
            DiffOperationType::LineInserted => "LINE_INSERTED",
        }
    }
    /// Creates an enum from field names used in the ProtoBuf definition.
    pub fn from_str_name(value: &str) -> ::core::option::Option<Self> {
        match value {
            "LINE_EQUAL" => Some(Self::LineEqual),
            "LINE_DIFFER" => Some(Self::LineDiffer),
            "LINE_DELETED" => Some(Self::LineDeleted),
            "LINE_INSERTED" => Some(Self::LineInserted),
            _ => None,
        }
    }
}
/// Generated client implementations.
pub mod submission_management_client {
    #![allow(unused_variables, dead_code, missing_docs, clippy::let_unit_value)]
    use tonic::codegen::*;
    use tonic::codegen::http::Uri;
    #[derive(Debug, Clone)]
    pub struct SubmissionManagementClient<T> {
        inner: tonic::client::Grpc<T>,
    }
    impl SubmissionManagementClient<tonic::transport::Channel> {
        /// Attempt to create a new client by connecting to a given endpoint.
        pub async fn connect<D>(dst: D) -> Result<Self, tonic::transport::Error>
        where
            D: TryInto<tonic::transport::Endpoint>,
            D::Error: Into<StdError>,
        {
            let conn = tonic::transport::Endpoint::new(dst)?.connect().await?;
            Ok(Self::new(conn))
        }
    }
    impl<T> SubmissionManagementClient<T>
    where
        T: tonic::client::GrpcService<tonic::body::BoxBody>,
        T::Error: Into<StdError>,
        T::ResponseBody: Body<Data = Bytes> + Send + 'static,
        <T::ResponseBody as Body>::Error: Into<StdError> + Send,
    {
        pub fn new(inner: T) -> Self {
            let inner = tonic::client::Grpc::new(inner);
            Self { inner }
        }
        pub fn with_origin(inner: T, origin: Uri) -> Self {
            let inner = tonic::client::Grpc::with_origin(inner, origin);
            Self { inner }
        }
        pub fn with_interceptor<F>(
            inner: T,
            interceptor: F,
        ) -> SubmissionManagementClient<InterceptedService<T, F>>
        where
            F: tonic::service::Interceptor,
            T::ResponseBody: Default,
            T: tonic::codegen::Service<
                http::Request<tonic::body::BoxBody>,
                Response = http::Response<
                    <T as tonic::client::GrpcService<tonic::body::BoxBody>>::ResponseBody,
                >,
            >,
            <T as tonic::codegen::Service<
                http::Request<tonic::body::BoxBody>,
            >>::Error: Into<StdError> + Send + Sync,
        {
            SubmissionManagementClient::new(InterceptedService::new(inner, interceptor))
        }
        /// Compress requests with the given encoding.
        ///
        /// This requires the server to support it otherwise it might respond with an
        /// error.
        #[must_use]
        pub fn send_compressed(mut self, encoding: CompressionEncoding) -> Self {
            self.inner = self.inner.send_compressed(encoding);
            self
        }
        /// Enable decompressing responses.
        #[must_use]
        pub fn accept_compressed(mut self, encoding: CompressionEncoding) -> Self {
            self.inner = self.inner.accept_compressed(encoding);
            self
        }
        /// Limits the maximum size of a decoded message.
        ///
        /// Default: `4MB`
        #[must_use]
        pub fn max_decoding_message_size(mut self, limit: usize) -> Self {
            self.inner = self.inner.max_decoding_message_size(limit);
            self
        }
        /// Limits the maximum size of an encoded message.
        ///
        /// Default: `usize::MAX`
        #[must_use]
        pub fn max_encoding_message_size(mut self, limit: usize) -> Self {
            self.inner = self.inner.max_encoding_message_size(limit);
            self
        }
        pub async fn submit_problem_solution(
            &mut self,
            request: impl tonic::IntoRequest<super::Submission>,
        ) -> std::result::Result<tonic::Response<super::Submission>, tonic::Status> {
            self.inner
                .ready()
                .await
                .map_err(|e| {
                    tonic::Status::new(
                        tonic::Code::Unknown,
                        format!("Service was not ready: {}", e.into()),
                    )
                })?;
            let codec = tonic::codec::ProstCodec::default();
            let path = http::uri::PathAndQuery::from_static(
                "/yajudge.SubmissionManagement/SubmitProblemSolution",
            );
            let mut req = request.into_request();
            req.extensions_mut()
                .insert(
                    GrpcMethod::new(
                        "yajudge.SubmissionManagement",
                        "SubmitProblemSolution",
                    ),
                );
            self.inner.unary(req, path, codec).await
        }
        pub async fn get_submissions(
            &mut self,
            request: impl tonic::IntoRequest<super::SubmissionFilter>,
        ) -> std::result::Result<tonic::Response<super::SubmissionList>, tonic::Status> {
            self.inner
                .ready()
                .await
                .map_err(|e| {
                    tonic::Status::new(
                        tonic::Code::Unknown,
                        format!("Service was not ready: {}", e.into()),
                    )
                })?;
            let codec = tonic::codec::ProstCodec::default();
            let path = http::uri::PathAndQuery::from_static(
                "/yajudge.SubmissionManagement/GetSubmissions",
            );
            let mut req = request.into_request();
            req.extensions_mut()
                .insert(
                    GrpcMethod::new("yajudge.SubmissionManagement", "GetSubmissions"),
                );
            self.inner.unary(req, path, codec).await
        }
        pub async fn get_submission_result(
            &mut self,
            request: impl tonic::IntoRequest<super::Submission>,
        ) -> std::result::Result<tonic::Response<super::Submission>, tonic::Status> {
            self.inner
                .ready()
                .await
                .map_err(|e| {
                    tonic::Status::new(
                        tonic::Code::Unknown,
                        format!("Service was not ready: {}", e.into()),
                    )
                })?;
            let codec = tonic::codec::ProstCodec::default();
            let path = http::uri::PathAndQuery::from_static(
                "/yajudge.SubmissionManagement/GetSubmissionResult",
            );
            let mut req = request.into_request();
            req.extensions_mut()
                .insert(
                    GrpcMethod::new(
                        "yajudge.SubmissionManagement",
                        "GetSubmissionResult",
                    ),
                );
            self.inner.unary(req, path, codec).await
        }
        pub async fn get_submission_list(
            &mut self,
            request: impl tonic::IntoRequest<super::SubmissionListQuery>,
        ) -> std::result::Result<
            tonic::Response<super::SubmissionListResponse>,
            tonic::Status,
        > {
            self.inner
                .ready()
                .await
                .map_err(|e| {
                    tonic::Status::new(
                        tonic::Code::Unknown,
                        format!("Service was not ready: {}", e.into()),
                    )
                })?;
            let codec = tonic::codec::ProstCodec::default();
            let path = http::uri::PathAndQuery::from_static(
                "/yajudge.SubmissionManagement/GetSubmissionList",
            );
            let mut req = request.into_request();
            req.extensions_mut()
                .insert(
                    GrpcMethod::new("yajudge.SubmissionManagement", "GetSubmissionList"),
                );
            self.inner.unary(req, path, codec).await
        }
        pub async fn subscribe_to_submission_list_notifications(
            &mut self,
            request: impl tonic::IntoRequest<super::SubmissionListNotificationsRequest>,
        ) -> std::result::Result<
            tonic::Response<tonic::codec::Streaming<super::SubmissionListEntry>>,
            tonic::Status,
        > {
            self.inner
                .ready()
                .await
                .map_err(|e| {
                    tonic::Status::new(
                        tonic::Code::Unknown,
                        format!("Service was not ready: {}", e.into()),
                    )
                })?;
            let codec = tonic::codec::ProstCodec::default();
            let path = http::uri::PathAndQuery::from_static(
                "/yajudge.SubmissionManagement/SubscribeToSubmissionListNotifications",
            );
            let mut req = request.into_request();
            req.extensions_mut()
                .insert(
                    GrpcMethod::new(
                        "yajudge.SubmissionManagement",
                        "SubscribeToSubmissionListNotifications",
                    ),
                );
            self.inner.server_streaming(req, path, codec).await
        }
        pub async fn rejudge(
            &mut self,
            request: impl tonic::IntoRequest<super::RejudgeRequest>,
        ) -> std::result::Result<tonic::Response<super::RejudgeRequest>, tonic::Status> {
            self.inner
                .ready()
                .await
                .map_err(|e| {
                    tonic::Status::new(
                        tonic::Code::Unknown,
                        format!("Service was not ready: {}", e.into()),
                    )
                })?;
            let codec = tonic::codec::ProstCodec::default();
            let path = http::uri::PathAndQuery::from_static(
                "/yajudge.SubmissionManagement/Rejudge",
            );
            let mut req = request.into_request();
            req.extensions_mut()
                .insert(GrpcMethod::new("yajudge.SubmissionManagement", "Rejudge"));
            self.inner.unary(req, path, codec).await
        }
        pub async fn subscribe_to_submission_result_notifications(
            &mut self,
            request: impl tonic::IntoRequest<super::Submission>,
        ) -> std::result::Result<
            tonic::Response<tonic::codec::Streaming<super::Submission>>,
            tonic::Status,
        > {
            self.inner
                .ready()
                .await
                .map_err(|e| {
                    tonic::Status::new(
                        tonic::Code::Unknown,
                        format!("Service was not ready: {}", e.into()),
                    )
                })?;
            let codec = tonic::codec::ProstCodec::default();
            let path = http::uri::PathAndQuery::from_static(
                "/yajudge.SubmissionManagement/SubscribeToSubmissionResultNotifications",
            );
            let mut req = request.into_request();
            req.extensions_mut()
                .insert(
                    GrpcMethod::new(
                        "yajudge.SubmissionManagement",
                        "SubscribeToSubmissionResultNotifications",
                    ),
                );
            self.inner.server_streaming(req, path, codec).await
        }
        /// announce grader alive and receive stream of submissions to be graded
        pub async fn set_external_service_status(
            &mut self,
            request: impl tonic::IntoRequest<super::ConnectedServiceStatus>,
        ) -> std::result::Result<tonic::Response<super::Empty>, tonic::Status> {
            self.inner
                .ready()
                .await
                .map_err(|e| {
                    tonic::Status::new(
                        tonic::Code::Unknown,
                        format!("Service was not ready: {}", e.into()),
                    )
                })?;
            let codec = tonic::codec::ProstCodec::default();
            let path = http::uri::PathAndQuery::from_static(
                "/yajudge.SubmissionManagement/SetExternalServiceStatus",
            );
            let mut req = request.into_request();
            req.extensions_mut()
                .insert(
                    GrpcMethod::new(
                        "yajudge.SubmissionManagement",
                        "SetExternalServiceStatus",
                    ),
                );
            self.inner.unary(req, path, codec).await
        }
        pub async fn receive_submissions_to_process(
            &mut self,
            request: impl tonic::IntoRequest<super::ConnectedServiceProperties>,
        ) -> std::result::Result<
            tonic::Response<tonic::codec::Streaming<super::Submission>>,
            tonic::Status,
        > {
            self.inner
                .ready()
                .await
                .map_err(|e| {
                    tonic::Status::new(
                        tonic::Code::Unknown,
                        format!("Service was not ready: {}", e.into()),
                    )
                })?;
            let codec = tonic::codec::ProstCodec::default();
            let path = http::uri::PathAndQuery::from_static(
                "/yajudge.SubmissionManagement/ReceiveSubmissionsToProcess",
            );
            let mut req = request.into_request();
            req.extensions_mut()
                .insert(
                    GrpcMethod::new(
                        "yajudge.SubmissionManagement",
                        "ReceiveSubmissionsToProcess",
                    ),
                );
            self.inner.server_streaming(req, path, codec).await
        }
        pub async fn get_submissions_to_diff(
            &mut self,
            request: impl tonic::IntoRequest<super::DiffViewRequest>,
        ) -> std::result::Result<
            tonic::Response<super::DiffViewResponse>,
            tonic::Status,
        > {
            self.inner
                .ready()
                .await
                .map_err(|e| {
                    tonic::Status::new(
                        tonic::Code::Unknown,
                        format!("Service was not ready: {}", e.into()),
                    )
                })?;
            let codec = tonic::codec::ProstCodec::default();
            let path = http::uri::PathAndQuery::from_static(
                "/yajudge.SubmissionManagement/GetSubmissionsToDiff",
            );
            let mut req = request.into_request();
            req.extensions_mut()
                .insert(
                    GrpcMethod::new(
                        "yajudge.SubmissionManagement",
                        "GetSubmissionsToDiff",
                    ),
                );
            self.inner.unary(req, path, codec).await
        }
        pub async fn take_submission_to_grade(
            &mut self,
            request: impl tonic::IntoRequest<super::ConnectedServiceProperties>,
        ) -> std::result::Result<tonic::Response<super::Submission>, tonic::Status> {
            self.inner
                .ready()
                .await
                .map_err(|e| {
                    tonic::Status::new(
                        tonic::Code::Unknown,
                        format!("Service was not ready: {}", e.into()),
                    )
                })?;
            let codec = tonic::codec::ProstCodec::default();
            let path = http::uri::PathAndQuery::from_static(
                "/yajudge.SubmissionManagement/TakeSubmissionToGrade",
            );
            let mut req = request.into_request();
            req.extensions_mut()
                .insert(
                    GrpcMethod::new(
                        "yajudge.SubmissionManagement",
                        "TakeSubmissionToGrade",
                    ),
                );
            self.inner.unary(req, path, codec).await
        }
        /// argument filled by id, status, grader_score, grader_name, grader_output, grader_errors
        pub async fn update_grader_output(
            &mut self,
            request: impl tonic::IntoRequest<super::Submission>,
        ) -> std::result::Result<tonic::Response<super::Submission>, tonic::Status> {
            self.inner
                .ready()
                .await
                .map_err(|e| {
                    tonic::Status::new(
                        tonic::Code::Unknown,
                        format!("Service was not ready: {}", e.into()),
                    )
                })?;
            let codec = tonic::codec::ProstCodec::default();
            let path = http::uri::PathAndQuery::from_static(
                "/yajudge.SubmissionManagement/UpdateGraderOutput",
            );
            let mut req = request.into_request();
            req.extensions_mut()
                .insert(
                    GrpcMethod::new("yajudge.SubmissionManagement", "UpdateGraderOutput"),
                );
            self.inner.unary(req, path, codec).await
        }
        /// manual submission status update
        pub async fn update_submission_status(
            &mut self,
            request: impl tonic::IntoRequest<super::Submission>,
        ) -> std::result::Result<tonic::Response<super::Submission>, tonic::Status> {
            self.inner
                .ready()
                .await
                .map_err(|e| {
                    tonic::Status::new(
                        tonic::Code::Unknown,
                        format!("Service was not ready: {}", e.into()),
                    )
                })?;
            let codec = tonic::codec::ProstCodec::default();
            let path = http::uri::PathAndQuery::from_static(
                "/yajudge.SubmissionManagement/UpdateSubmissionStatus",
            );
            let mut req = request.into_request();
            req.extensions_mut()
                .insert(
                    GrpcMethod::new(
                        "yajudge.SubmissionManagement",
                        "UpdateSubmissionStatus",
                    ),
                );
            self.inner.unary(req, path, codec).await
        }
    }
}
/// Generated client implementations.
pub mod course_content_provider_client {
    #![allow(unused_variables, dead_code, missing_docs, clippy::let_unit_value)]
    use tonic::codegen::*;
    use tonic::codegen::http::Uri;
    #[derive(Debug, Clone)]
    pub struct CourseContentProviderClient<T> {
        inner: tonic::client::Grpc<T>,
    }
    impl CourseContentProviderClient<tonic::transport::Channel> {
        /// Attempt to create a new client by connecting to a given endpoint.
        pub async fn connect<D>(dst: D) -> Result<Self, tonic::transport::Error>
        where
            D: TryInto<tonic::transport::Endpoint>,
            D::Error: Into<StdError>,
        {
            let conn = tonic::transport::Endpoint::new(dst)?.connect().await?;
            Ok(Self::new(conn))
        }
    }
    impl<T> CourseContentProviderClient<T>
    where
        T: tonic::client::GrpcService<tonic::body::BoxBody>,
        T::Error: Into<StdError>,
        T::ResponseBody: Body<Data = Bytes> + Send + 'static,
        <T::ResponseBody as Body>::Error: Into<StdError> + Send,
    {
        pub fn new(inner: T) -> Self {
            let inner = tonic::client::Grpc::new(inner);
            Self { inner }
        }
        pub fn with_origin(inner: T, origin: Uri) -> Self {
            let inner = tonic::client::Grpc::with_origin(inner, origin);
            Self { inner }
        }
        pub fn with_interceptor<F>(
            inner: T,
            interceptor: F,
        ) -> CourseContentProviderClient<InterceptedService<T, F>>
        where
            F: tonic::service::Interceptor,
            T::ResponseBody: Default,
            T: tonic::codegen::Service<
                http::Request<tonic::body::BoxBody>,
                Response = http::Response<
                    <T as tonic::client::GrpcService<tonic::body::BoxBody>>::ResponseBody,
                >,
            >,
            <T as tonic::codegen::Service<
                http::Request<tonic::body::BoxBody>,
            >>::Error: Into<StdError> + Send + Sync,
        {
            CourseContentProviderClient::new(InterceptedService::new(inner, interceptor))
        }
        /// Compress requests with the given encoding.
        ///
        /// This requires the server to support it otherwise it might respond with an
        /// error.
        #[must_use]
        pub fn send_compressed(mut self, encoding: CompressionEncoding) -> Self {
            self.inner = self.inner.send_compressed(encoding);
            self
        }
        /// Enable decompressing responses.
        #[must_use]
        pub fn accept_compressed(mut self, encoding: CompressionEncoding) -> Self {
            self.inner = self.inner.accept_compressed(encoding);
            self
        }
        /// Limits the maximum size of a decoded message.
        ///
        /// Default: `4MB`
        #[must_use]
        pub fn max_decoding_message_size(mut self, limit: usize) -> Self {
            self.inner = self.inner.max_decoding_message_size(limit);
            self
        }
        /// Limits the maximum size of an encoded message.
        ///
        /// Default: `usize::MAX`
        #[must_use]
        pub fn max_encoding_message_size(mut self, limit: usize) -> Self {
            self.inner = self.inner.max_encoding_message_size(limit);
            self
        }
        pub async fn get_course_public_content(
            &mut self,
            request: impl tonic::IntoRequest<super::CourseContentRequest>,
        ) -> std::result::Result<
            tonic::Response<super::CourseContentResponse>,
            tonic::Status,
        > {
            self.inner
                .ready()
                .await
                .map_err(|e| {
                    tonic::Status::new(
                        tonic::Code::Unknown,
                        format!("Service was not ready: {}", e.into()),
                    )
                })?;
            let codec = tonic::codec::ProstCodec::default();
            let path = http::uri::PathAndQuery::from_static(
                "/yajudge.CourseContentProvider/GetCoursePublicContent",
            );
            let mut req = request.into_request();
            req.extensions_mut()
                .insert(
                    GrpcMethod::new(
                        "yajudge.CourseContentProvider",
                        "GetCoursePublicContent",
                    ),
                );
            self.inner.unary(req, path, codec).await
        }
        pub async fn get_problem_full_content(
            &mut self,
            request: impl tonic::IntoRequest<super::ProblemContentRequest>,
        ) -> std::result::Result<
            tonic::Response<super::ProblemContentResponse>,
            tonic::Status,
        > {
            self.inner
                .ready()
                .await
                .map_err(|e| {
                    tonic::Status::new(
                        tonic::Code::Unknown,
                        format!("Service was not ready: {}", e.into()),
                    )
                })?;
            let codec = tonic::codec::ProstCodec::default();
            let path = http::uri::PathAndQuery::from_static(
                "/yajudge.CourseContentProvider/GetProblemFullContent",
            );
            let mut req = request.into_request();
            req.extensions_mut()
                .insert(
                    GrpcMethod::new(
                        "yajudge.CourseContentProvider",
                        "GetProblemFullContent",
                    ),
                );
            self.inner.unary(req, path, codec).await
        }
    }
}

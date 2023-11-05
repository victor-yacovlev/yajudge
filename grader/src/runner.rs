use anyhow::Result;
use std::{
    ffi::{CString},
    path::{Path, PathBuf},
    process::Command,
};

use nix::{
    mount::{mount, MsFlags},
    sched::{unshare, CloneFlags},
    sys::{
        resource::{setrlimit, Resource},
        wait::{waitpid},
    },
    unistd::{
        chdir, chroot, execvp, fork, getgid, getpid, getuid,
        ForkResult::{Child, Parent},
        Pid,
    },
};
use slog::Logger;

use crate::{generated::yajudge::GradingLimits, storage::StorageManager};

pub trait Runner {
    fn push_stdin(&mut self, stdin_data: &Vec<u8>);
    fn set_relative_workdir(&mut self, path: &Path);
    fn read_stdout(&mut self) -> Vec<u8>;
    fn read_stderr(&mut self) -> Vec<u8>;
    fn get_exit_status(&self) -> u8;
    fn start(&mut self, program: &String, arguments: &Vec<String>) -> Result<()>;
    fn process_envents_until_finished(&mut self) -> Result<()>;
}

struct LaunchCmd {
    program: String,
    arguments: Vec<String>,
}

struct ChildProcess {
    pid: Pid,
}

pub struct IsolatedRunner {
    logger: Logger,
    limits: Option<GradingLimits>,
    system_root: PathBuf,
    problem_root: PathBuf,
    submission_root: PathBuf,

    relative_workdir: PathBuf,
    exit_status: u8,

    child: Option<ChildProcess>,
}

impl IsolatedRunner {
    pub fn new(
        logger: Logger,
        limits: Option<GradingLimits>,
        system_root: &Path,
        problem_root: &Path,
        submission_root: &Path,
    ) -> IsolatedRunner {
        IsolatedRunner {
            logger,
            limits,
            system_root: PathBuf::from(system_root),
            problem_root: PathBuf::from(problem_root),
            submission_root: PathBuf::from(submission_root),

            relative_workdir: PathBuf::from("/"),
            exit_status: 0,

            child: None,
        }
    }

    fn enter_initial_namespace(allow_network: bool) -> Result<()> {
        let uid = getuid();
        let gid = getgid();
        let uid_map_line = format!("0 {} 1", uid);
        let gid_map_line = format!("0 {} 1", gid);

        let mut unshare_flags = CloneFlags::empty();
        unshare_flags.insert(CloneFlags::CLONE_NEWUSER);
        unshare_flags.insert(CloneFlags::CLONE_NEWNS);
        unshare_flags.insert(CloneFlags::CLONE_NEWIPC);
        if !allow_network {
            unshare_flags.insert(CloneFlags::CLONE_NEWNET);
            unshare_flags.insert(CloneFlags::CLONE_NEWUTS);
        }
        unshare(unshare_flags)?;

        std::fs::write("/proc/self/uid_map", &uid_map_line)?;
        std::fs::write("/proc/self/setgroups", "deny")?;
        std::fs::write("/proc/self/gid_map", &gid_map_line)?;

        Ok(())
    }

    fn setup_localhost() -> Result<()> {
        // TODO implement interface up without using external command
        let ip_status_result = Command::new("ip")
            .args(["link", "set", "dev", "lo", "up"])
            .status();

        if ip_status_result.is_err() {
            let err = ip_status_result.unwrap_err();
            return Err(anyhow::Error::msg(format!(
                "can't setup localhost: {}",
                err
            )));
        }

        if !ip_status_result.unwrap().success() {
            return Err(anyhow::Error::msg("setup localhost failed"));
        }

        Ok(())
    }

    fn create_and_enter_new_root_dir(
        mount_overlay_options: String,
        overlay_mergedir: &Path,
        initial_cwd: &Path,
    ) -> Result<()> {
        let mount_flags = MsFlags::empty();
        mount(
            Some("overlay"),
            overlay_mergedir,
            Some("overlay"),
            mount_flags,
            Some(mount_overlay_options.as_str()),
        )?;
        chroot(overlay_mergedir)?;
        std::fs::create_dir_all("/tmp")?;
        std::fs::create_dir_all("/proc")?;
        mount(
            Some("tmpfs"),
            "/tmp",
            Some("tmpfs"),
            mount_flags,
            None::<&str>,
        )?;
        chdir(initial_cwd)?;

        Ok(())
    }

    fn unshare_pid_namespace() -> Result<()> {
        let mut unshare_flags = CloneFlags::empty();
        unshare_flags.insert(CloneFlags::CLONE_NEWPID);
        unshare(unshare_flags)?;

        Ok(())
    }

    fn mount_proc_fs() -> Result<()> {
        let mount_flags = MsFlags::empty();
        mount(
            Some("proc"),
            "/proc",
            Some("proc"),
            mount_flags,
            None::<&str>,
        )?;

        Ok(())
    }

    fn setup_cgroup_limits(_limits: &GradingLimits) -> Result<()> {
        // TODO implement me
        Ok(())
    }

    fn set_rlim_value(key: Resource, value: i32) -> Result<()> {
        setrlimit(key, value as u64, value as u64)?;

        Ok(())
    }

    fn setup_posix_limits(limits: &GradingLimits) -> Result<()> {
        if limits.cpu_time_limit_sec != 0 {
            Self::set_rlim_value(Resource::RLIMIT_CPU, limits.cpu_time_limit_sec)?;
        }
        if limits.stack_size_limit_mb != 0 {
            Self::set_rlim_value(
                Resource::RLIMIT_STACK,
                limits.stack_size_limit_mb * 1024 * 1024,
            )?;
        }
        if limits.fd_count_limit != 0 {
            Self::set_rlim_value(Resource::RLIMIT_NOFILE, limits.fd_count_limit)?;
        }
        // to prevent fork-bombs in case if croup-limits not set
        Self::set_rlim_value(Resource::RLIMIT_NPROC, 5000)?;

        Ok(())
    }

    fn tune_new_process(
        limits: Option<GradingLimits>,
        mount_overlay_options: String,
        overlay_mergedir: &Path,
        initial_cwd: &Path,
    ) -> Result<()> {
        println!("started child {}", getpid());
        let allow_network = if let Some(limits) = limits.as_ref() {
            limits.allow_network
        } else {
            false
        };
        Self::enter_initial_namespace(allow_network)?;
        if !allow_network {
            Self::setup_localhost()?;
        }
        if let Some(limits) = limits.as_ref() {
            Self::setup_cgroup_limits(&limits)?;
        }
        Self::create_and_enter_new_root_dir(mount_overlay_options, overlay_mergedir, initial_cwd)?;
        if let Some(limits) = limits.as_ref() {
            Self::setup_posix_limits(&limits)?;
        }

        Ok(())
    }

    fn start_root_process_then_start_childs(
        main: LaunchCmd,
        coprocesses: Vec<LaunchCmd>,
    ) -> anyhow::Result<()> {
        Self::unshare_pid_namespace()?;
        let fork_result = unsafe { fork()? };
        match fork_result {
            Parent { child } => {
                let wait_status = waitpid(child, None)?;
                let _ = wait_status;
            }
            Child => {
                Self::mount_proc_fs()?;
                Self::start_child_processes_in_new_pid_namespace(main, coprocesses)?;
            }
        };

        Ok(())
    }

    fn start_child_processes_in_new_pid_namespace(
        main: LaunchCmd,
        _coprocesses: Vec<LaunchCmd>,
    ) -> Result<()> {
        // TODO launch coprocesses

        let filename = CString::new(main.program).unwrap();
        let mut arg_strings = Vec::<CString>::with_capacity(main.arguments.len() + 1);
        arg_strings.push(filename.clone());
        for argument in main.arguments {
            let arg_cstring = CString::new(argument).unwrap();
            arg_strings.push(arg_cstring);
        }
        let fork_result = unsafe { fork()? };
        match fork_result {
            Parent { child } => {
                let _ = waitpid(child, None);
            }
            Child => {
                execvp(&filename, &arg_strings)?;
                println!("execvp failed");
            }
        }
        Ok(())
    }

    fn prepare_overlay_to_mount(&self) -> Result<(String, PathBuf)> {
        let workdir_path = &self.submission_root.join("workdir").canonicalize()?;
        let mergedir_path = &self.submission_root.join("mergedir").canonicalize()?;
        StorageManager::mkdir(&workdir_path)?;
        StorageManager::mkdir(&mergedir_path)?;
        let system_path = &self.system_root.canonicalize()?;
        let problem_path = &self.problem_root.join("lowerdir").canonicalize()?;
        let lowerdir = format!(
            "{}:{}",
            system_path.to_str().unwrap(),
            problem_path.to_str().unwrap()
        );
        let upperdir_path = &self.submission_root.join("upperdir").canonicalize()?;
        let upperdir = upperdir_path.to_str().unwrap();
        let workdir = workdir_path.to_str().unwrap();
        let mergedir = mergedir_path;
        let options_string = format!(
            "lowerdir={},upperdir={},workdir={}",
            lowerdir, upperdir, workdir,
        );

        Ok((options_string, mergedir.to_owned()))
    }
}

impl Runner for IsolatedRunner {
    fn push_stdin(&mut self, _stdin_data: &Vec<u8>) {
        todo!()
    }

    fn set_relative_workdir(&mut self, path: &Path) {
        self.relative_workdir = PathBuf::from(path);
    }

    fn read_stdout(&mut self) -> Vec<u8> {
        todo!()
    }

    fn read_stderr(&mut self) -> Vec<u8> {
        todo!()
    }

    fn get_exit_status(&self) -> u8 {
        return self.exit_status;
    }

    fn start(&mut self, _program: &String, _arguments: &Vec<String>) -> Result<()> {
        let main_process = LaunchCmd {
            program: "bash".into(),
            arguments: vec!["-c".into(), "ls -la /proc".into()],
        };

        let limits = self.limits.clone();
        let (mount_overlay_options, overlay_mergedir) = self.prepare_overlay_to_mount()?;
        let initial_cwd = self.relative_workdir.clone();

        let fork_result = unsafe { fork()? };
        match fork_result {
            Parent { child } => {
                let child_process = ChildProcess { pid: child.clone() };
                self.child = Some(child_process);
                let wait_status = waitpid(child, None)?;
                let _ = wait_status;
            }
            Child => {
                Self::tune_new_process(
                    limits,
                    mount_overlay_options,
                    &overlay_mergedir,
                    &initial_cwd,
                )?;
                Self::start_root_process_then_start_childs(main_process, vec![])?;
            }
        };

        Ok(())
    }

    fn process_envents_until_finished(&mut self) -> Result<()> {
        // todo!()
        Ok(())
    }
}

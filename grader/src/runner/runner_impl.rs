use super::process_monitor::{ProcessEvent, ProcessMonitor};

use anyhow::Result;
use nix::{self, fcntl, mount, sched, sys, unistd};
use std::{
    ffi::CString,
    os::fd::{FromRawFd, OwnedFd, RawFd},
    path::{Path, PathBuf},
    process::Command,
};
use tokio::sync::mpsc::{unbounded_channel, UnboundedReceiver};

use serde::{Deserialize, Serialize};
use slog::Logger;

use crate::{generated::yajudge::GradingLimits, storage::StorageManager};

use super::{CommandOutput, ExitResult, LaunchCmd, Runner};

#[derive(Serialize, Deserialize, Debug)]
pub enum LogMessage {
    Dbg(String),
    Err(String),
}

impl Runner {
    pub fn new(
        logger: Logger,
        limits: Option<GradingLimits>,
        system_root: &Path,
        problem_root: &Path,
        submission_root: &Path,
    ) -> Runner {
        Runner {
            logger,
            limits,
            system_root: PathBuf::from(system_root),
            problem_root: PathBuf::from(problem_root),
            submission_root: PathBuf::from(submission_root),

            relative_workdir: PathBuf::from("/"),
            exit_result: None,

            child: None,

            stdout_sender: None,
            stdout_receiver: None,
            stderr_sender: None,
            stderr_receiver: None,
        }
    }

    unsafe fn enter_initial_namespace(_log_pipe: RawFd, allow_network: bool) -> Result<()> {
        let uid = unistd::getuid();
        let gid = unistd::getgid();
        let uid_map_line = format!("0 {} 1", uid);
        let gid_map_line = format!("0 {} 1", gid);

        let mut unshare_flags = sched::CloneFlags::empty();
        unshare_flags.insert(sched::CloneFlags::CLONE_NEWUSER);
        unshare_flags.insert(sched::CloneFlags::CLONE_NEWNS);
        unshare_flags.insert(sched::CloneFlags::CLONE_NEWIPC);
        if !allow_network {
            unshare_flags.insert(sched::CloneFlags::CLONE_NEWNET);
            unshare_flags.insert(sched::CloneFlags::CLONE_NEWUTS);
        }
        sched::unshare(unshare_flags)?;

        std::fs::write("/proc/self/uid_map", &uid_map_line)?;
        std::fs::write("/proc/self/setgroups", "deny")?;
        std::fs::write("/proc/self/gid_map", &gid_map_line)?;

        Ok(())
    }

    fn setup_localhost(_log_pipe: RawFd) -> Result<()> {
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
        _log_pipe: RawFd,
        mount_overlay_options: String,
        overlay_mergedir: &Path,
        initial_cwd: &Path,
    ) -> Result<()> {
        let mount_flags = mount::MsFlags::empty();
        mount::mount(
            Some("overlay"),
            overlay_mergedir,
            Some("overlay"),
            mount_flags,
            Some(mount_overlay_options.as_str()),
        )?;
        unistd::chroot(overlay_mergedir)?;
        std::fs::create_dir_all("/tmp")?;
        std::fs::create_dir_all("/proc")?;
        mount::mount(
            Some("tmpfs"),
            "/tmp",
            Some("tmpfs"),
            mount_flags,
            None::<&str>,
        )?;
        unistd::chdir(initial_cwd)?;

        Ok(())
    }

    fn unshare_pid_namespace(_log_pipe: RawFd) -> Result<()> {
        let mut unshare_flags = sched::CloneFlags::empty();
        unshare_flags.insert(sched::CloneFlags::CLONE_NEWPID);
        sched::unshare(unshare_flags)?;

        Ok(())
    }

    fn mount_proc_fs(_log_pipe: RawFd) -> Result<()> {
        let mount_flags = mount::MsFlags::empty();
        mount::mount(
            Some("proc"),
            "/proc",
            Some("proc"),
            mount_flags,
            None::<&str>,
        )?;

        Ok(())
    }

    fn setup_cgroup_limits(_log_pipe: RawFd, _limits: &GradingLimits) -> Result<()> {
        // TODO implement me
        Ok(())
    }

    fn set_rlim_value(key: sys::resource::Resource, value: i32) -> Result<()> {
        sys::resource::setrlimit(key, value as u64, value as u64)?;

        Ok(())
    }

    fn setup_posix_limits(_log_pipe: RawFd, limits: &GradingLimits) -> Result<()> {
        if limits.cpu_time_limit_sec != 0 {
            Self::set_rlim_value(
                sys::resource::Resource::RLIMIT_CPU,
                limits.cpu_time_limit_sec,
            )?;
        }
        if limits.stack_size_limit_mb != 0 {
            Self::set_rlim_value(
                sys::resource::Resource::RLIMIT_STACK,
                limits.stack_size_limit_mb * 1024 * 1024,
            )?;
        }
        if limits.fd_count_limit != 0 {
            Self::set_rlim_value(
                sys::resource::Resource::RLIMIT_NOFILE,
                limits.fd_count_limit,
            )?;
        }
        // to prevent fork-bombs in case if croup-limits not set
        Self::set_rlim_value(sys::resource::Resource::RLIMIT_NPROC, 5000)?;

        Ok(())
    }

    unsafe fn tune_new_process(
        log_pipe: RawFd,
        limits: Option<GradingLimits>,
        mount_overlay_options: String,
        overlay_mergedir: &Path,
        initial_cwd: &Path,
    ) -> Result<()> {
        let allow_network = if let Some(limits) = limits.as_ref() {
            limits.allow_network
        } else {
            false
        };
        Self::enter_initial_namespace(log_pipe, allow_network)?;
        if !allow_network {
            Self::setup_localhost(log_pipe)?;
        }
        if let Some(limits) = limits.as_ref() {
            Self::setup_cgroup_limits(log_pipe, &limits)?;
        }
        Self::create_and_enter_new_root_dir(
            log_pipe,
            mount_overlay_options,
            overlay_mergedir,
            initial_cwd,
        )?;
        if let Some(limits) = limits.as_ref() {
            Self::setup_posix_limits(log_pipe, &limits)?;
        }

        Ok(())
    }

    unsafe fn start_root_process_then_start_childs(
        log_pipe: RawFd,
        main: LaunchCmd,
        coprocesses: Vec<LaunchCmd>,
    ) -> anyhow::Result<()> {
        Self::unshare_pid_namespace(log_pipe)?;
        let fork_result = unistd::fork()?;
        match fork_result {
            unistd::ForkResult::Child => {
                if let Err(error) = Self::mount_proc_fs(log_pipe) {
                    Self::fatal_error(log_pipe, error);
                }
                if let Err(error) =
                    Self::start_child_processes_in_new_pid_namespace(log_pipe, main, coprocesses)
                {
                    Self::fatal_error(log_pipe, error);
                }
            }
            unistd::ForkResult::Parent { child } => {
                let exit_result = Self::wait_for_finished_or_killed(log_pipe, child)?;
                Self::rethrow_exit_result(log_pipe, exit_result);
            }
        };

        Ok(())
    }

    unsafe fn start_child_processes_in_new_pid_namespace(
        log_pipe: RawFd,
        main: LaunchCmd,
        _coprocesses: Vec<LaunchCmd>,
    ) -> Result<()> {
        // TODO launch coprocesses

        let filename = CString::new(main.program.clone()).unwrap();
        let mut arg_strings = Vec::<CString>::with_capacity(main.arguments.len() + 1);
        arg_strings.push(filename.clone());
        for argument in &main.arguments {
            let arg_cstring = CString::new(argument.clone()).unwrap();
            arg_strings.push(arg_cstring);
        }
        let fork_result = unistd::fork()?;
        match fork_result {
            unistd::ForkResult::Child => {
                unistd::execvp(filename.as_c_str(), &arg_strings)?;
                Self::fatal_error(
                    log_pipe,
                    anyhow!(
                        "execvp({}, {}) failed",
                        main.program,
                        main.arguments.join(" ")
                    ),
                );
            }
            unistd::ForkResult::Parent { child } => {
                let exit_result = Self::wait_for_finished_or_killed(log_pipe, child)?;
                Self::debug_message(
                    log_pipe,
                    format!(
                        "Process with isolated pid={} finished with result: {}",
                        child,
                        exit_result.to_string()
                    )
                    .as_str(),
                );
                Self::rethrow_exit_result(log_pipe, exit_result);
            }
        }
        Ok(())
    }

    fn prepare_overlay_to_mount(&self) -> Result<(String, PathBuf)> {
        let workdir_path = &self.submission_root.join("workdir");
        let mergedir_path = &self.submission_root.join("mergedir");
        StorageManager::mkdir(&workdir_path)?;
        StorageManager::mkdir(&mergedir_path)?;
        let system_path = &self.system_root;
        let problem_path = &self.problem_root.join("lowerdir");
        let lowerdir = format!(
            "{}:{}",
            system_path.to_str().unwrap(),
            problem_path.to_str().unwrap()
        );
        let upperdir_path = &self.submission_root.join("upperdir");
        let upperdir = upperdir_path.to_str().unwrap();
        let workdir = workdir_path.to_str().unwrap();
        let mergedir = mergedir_path;
        let options_string = format!(
            "lowerdir={},upperdir={},workdir={}",
            lowerdir, upperdir, workdir,
        );

        Ok((options_string, mergedir.to_owned()))
    }

    unsafe fn wait_for_finished_or_killed(
        _log_pipe: RawFd,
        pid: unistd::Pid,
    ) -> Result<ExitResult> {
        let result = loop {
            let wait_status = sys::wait::waitpid(pid, None)?;
            match wait_status {
                sys::wait::WaitStatus::Exited(_, exit_status) => {
                    break ExitResult::Finished(exit_status as u8)
                }
                sys::wait::WaitStatus::Signaled(_, signal, _) => {
                    break ExitResult::Killed(signal as u8);
                }
                _ => continue,
            }
        };
        return Ok(result);
    }

    // This function must be called only from child process!
    fn rethrow_exit_result(log_pipe: RawFd, exit_result: ExitResult) {
        match exit_result {
            ExitResult::Finished(status) => std::process::exit(status as i32),
            ExitResult::Killed(signum) => {
                let _ = sys::signal::raise(sys::signal::Signal::try_from(signum as i32).unwrap());
            }
            _ => {
                Self::fatal_error(
                    log_pipe,
                    anyhow!(
                        "This case must not appear in child process: {}",
                        &exit_result.to_string()
                    ),
                );
            }
        }
    }

    fn read_all_from_optional_receiver(
        receiver: Option<&mut UnboundedReceiver<Vec<u8>>>,
    ) -> Vec<u8> {
        let mut result = Vec::<u8>::new();
        if let Some(receiver) = receiver {
            loop {
                let data = receiver.blocking_recv();
                if data.is_none() {
                    break;
                }
                result.extend(data.unwrap());
            }
        }

        result
    }

    pub fn push_stdin(&mut self, _stdin_data: &Vec<u8>) {
        todo!()
    }

    pub fn set_relative_workdir(&mut self, path: &Path) {
        self.relative_workdir = PathBuf::from(path);
    }

    pub fn read_all_stdout(&mut self) -> Vec<u8> {
        Self::read_all_from_optional_receiver(self.stdout_receiver.as_mut())
    }

    pub fn read_all_stderr(&mut self) -> Vec<u8> {
        Self::read_all_from_optional_receiver(self.stderr_receiver.as_mut())
    }

    pub fn get_exit_status(&mut self) -> Result<ExitResult> {
        match &self.exit_result {
            None => Err(anyhow!("Process not finished")),
            Some(result) => Ok(result.clone()),
        }
    }

    fn write_to_log(log: RawFd, message: &LogMessage) {
        let data = postcard::to_allocvec(message).unwrap();
        let _ = unistd::write(log, &data).unwrap();
    }

    fn debug_message(log: RawFd, message: &str) {
        Self::write_to_log(log, &LogMessage::Dbg(message.to_string()));
    }

    fn fatal_error(log: RawFd, error: anyhow::Error) {
        let message = error.to_string();
        Self::write_to_log(log, &LogMessage::Err(message));
        let _ = unistd::close(log);
        let _ = unistd::sleep(5);
        let _ = sys::signal::raise(sys::signal::SIGABRT);
    }

    pub fn start(&mut self, program: &String, arguments: &Vec<String>) -> Result<()> {
        let main_process = LaunchCmd {
            program: program.clone(),
            arguments: arguments.clone(),
        };

        let limits = self.limits.clone();
        let (mount_overlay_options, overlay_mergedir) = self.prepare_overlay_to_mount()?;
        let initial_cwd = self.relative_workdir.clone();

        let (stdin_pipe_0, stdin_pipe_1) = unistd::pipe()?;
        let (stdout_pipe_0, stdout_pipe_1) = unistd::pipe2(fcntl::OFlag::O_NONBLOCK)?;
        let (stderr_pipe_0, stderr_pipe_1) = unistd::pipe2(fcntl::OFlag::O_NONBLOCK)?;
        let (log_pipe_0, log_pipe_1) =
            unistd::pipe2(fcntl::OFlag::O_NONBLOCK | fcntl::OFlag::O_CLOEXEC)?;

        let (stdout_sender, stdout_receiver) = unbounded_channel();
        let (stderr_sender, stderr_receiver) = unbounded_channel();
        self.stdout_sender = Some(stdout_sender);
        self.stderr_sender = Some(stderr_sender);
        self.stdout_receiver = Some(stdout_receiver);
        self.stderr_receiver = Some(stderr_receiver);

        let fork_result = unsafe { unistd::fork()? };
        match fork_result {
            unistd::ForkResult::Child => unsafe {
                let _ = unistd::dup2(stdin_pipe_0, 0);
                let _ = unistd::dup2(stdout_pipe_1, 1);
                let _ = unistd::dup2(stderr_pipe_1, 2);
                let _ = unistd::close(stdin_pipe_0);
                let _ = unistd::close(stdout_pipe_1);
                let _ = unistd::close(stderr_pipe_1);

                let log_pipe = log_pipe_1;

                let status = Self::tune_new_process(
                    log_pipe,
                    limits,
                    mount_overlay_options,
                    &overlay_mergedir,
                    &initial_cwd,
                );

                if let Err(error) = status {
                    Self::fatal_error(log_pipe, error);
                }

                let status =
                    Self::start_root_process_then_start_childs(log_pipe, main_process, vec![]);
                if let Err(error) = status {
                    Self::fatal_error(log_pipe, error);
                }
            },
            unistd::ForkResult::Parent { child } => {
                let _ = unistd::close(stdin_pipe_0);
                let _ = unistd::close(stdout_pipe_1);
                let _ = unistd::close(stderr_pipe_1);
                let (real_time_limit_sec, stdout_limit_mb, stderr_limit_mb) = match limits {
                    None => (0, 0, 0),
                    Some(lim) => (
                        lim.real_time_limit_sec,
                        lim.stdout_size_limit_mb,
                        lim.stderr_size_limit_mb,
                    ),
                };
                let stdin = unsafe { OwnedFd::from_raw_fd(stdin_pipe_1) };
                let stdout = unsafe { OwnedFd::from_raw_fd(stdout_pipe_0) };
                let stderr = unsafe { OwnedFd::from_raw_fd(stderr_pipe_0) };
                let log = unsafe { OwnedFd::from_raw_fd(log_pipe_0) };
                let child_process = ProcessMonitor::new(
                    stdin,
                    stdout,
                    stderr,
                    log,
                    child,
                    real_time_limit_sec,
                    stdout_limit_mb,
                    stderr_limit_mb,
                )?;
                self.child = Some(child_process);
            }
        };

        Ok(())
    }

    pub fn process_events_until_finished(&mut self) -> Result<()> {
        if self.child.is_none() {
            return Err(anyhow!("Process not started"));
        }

        let child = self.child.as_mut().unwrap();

        loop {
            let event_option = child.next_event()?;
            if event_option.is_none() {
                continue;
            }
            let event = event_option.unwrap();
            match event {
                ProcessEvent::Finished(exit_result) => {
                    self.exit_result = Some(exit_result);
                    break;
                }
                ProcessEvent::Timeout => {
                    self.exit_result = Some(ExitResult::Timeout);
                    break;
                }
                ProcessEvent::StdoutLimit => {
                    self.exit_result = Some(ExitResult::StdoutLimit);
                    break;
                }
                ProcessEvent::StderrLimit => {
                    self.exit_result = Some(ExitResult::StderrLimit);
                    break;
                }
                ProcessEvent::StdoutData(data) => {
                    if data.len() > 0 {
                        self.stdout_sender
                            .as_mut()
                            .expect("No stdout sender channel")
                            .send(data)
                            .unwrap();
                    }
                }
                ProcessEvent::StderrData(data) => {
                    if data.len() > 0 {
                        self.stderr_sender
                            .as_mut()
                            .expect("No stderr sender channel")
                            .send(data)
                            .unwrap();
                    }
                }
                ProcessEvent::DebugMessage(message) => {
                    debug!(self.logger, "{}", message);
                }
            }
        }

        self.stdout_sender = None;
        self.stderr_sender = None;

        Ok(())
    }

    pub fn reset(&mut self) {
        self.exit_result = None;
        self.child = None;
        if let Some(stdout) = &mut self.stdout_receiver {
            stdout.close();
        }
        if let Some(stderr) = &mut self.stderr_receiver {
            stderr.close();
        }
        self.stdout_receiver = None;
        self.stderr_receiver = None;
    }

    pub fn run_command(&mut self, program: &str, args: Vec<&str>) -> Result<CommandOutput> {
        self.reset();
        let program_string = String::from(program);
        let mut args_strings = Vec::<String>::with_capacity(args.len());
        for arg in args {
            let arg_string: String = String::from(arg);
            args_strings.push(arg_string);
        }
        self.start(&program_string, &args_strings)?;
        self.process_events_until_finished()?;
        let exit_status = self.get_exit_status()?;
        let stdout = self.read_all_stdout();
        let stderr = self.read_all_stderr();

        let command_output = CommandOutput {
            exit_status,
            stdout,
            stderr,
        };

        Ok(command_output)
    }
}

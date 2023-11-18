use anyhow::Result;
use std::{
    ffi::CString,
    path::{Path, PathBuf},
    process::Command,
};
use tokio::sync::mpsc::{unbounded_channel, UnboundedReceiver, UnboundedSender};

use nix::{
    mount::{mount, MsFlags},
    sched::{unshare, CloneFlags},
    sys::{
        resource::{setrlimit, Resource},
        wait::{waitpid, WaitStatus},
    },
    unistd::{
        chdir, chroot, execvp, fork, getgid, getpid, getuid,
        ForkResult::{Child, Parent},
        Pid,
    },
};
use slog::Logger;

use crate::{generated::yajudge::GradingLimits, storage::StorageManager};

#[derive(Clone)]
pub enum ExitResult {
    Finished(u8),
    Killed(u8),
    Timeout,
    StdoutLimit,
    StderrLimit,
}

impl ExitResult {
    pub fn is_success(&self) -> bool {
        match self {
            ExitResult::Finished(status) => 0 == *status,
            ExitResult::Killed(_) => false,
            ExitResult::Timeout => false,
            ExitResult::StdoutLimit => false,
            ExitResult::StderrLimit => false,
        }
    }
}

#[derive(Clone)]
pub struct CommandOutput {
    pub exit_status: ExitResult,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
}

impl CommandOutput {
    pub fn is_success(&self) -> bool {
        match self.exit_status {
            ExitResult::Finished(status) => 0 == status,
            _ => false,
        }
    }

    pub fn stdout_as_string(&self) -> String {
        String::from_utf8(self.stdout.clone()).expect("Can't convert command stdout to utf-8")
    }

    pub fn stderr_as_string(&self) -> String {
        String::from_utf8(self.stderr.clone()).expect("Can't convert command stderr to utf-8")
    }

    pub fn get_error_message(maybe_output: &Result<CommandOutput>) -> Option<String> {
        match maybe_output {
            Err(e) => Some(e.to_string()),
            Ok(r) => {
                if r.is_success() {
                    None
                } else {
                    let stderr = r.stderr_as_string();
                    let message = if !stderr.is_empty() {
                        stderr
                    } else {
                        match r.exit_status {
                            ExitResult::Finished(st) => format!("Exited with status {}", st),
                            ExitResult::Killed(sig) => format!("Killed by signal {}", sig),
                            ExitResult::Timeout => format!("Killed by timeout"),
                            ExitResult::StdoutLimit => format!("Stdout limit"),
                            ExitResult::StderrLimit => format!("Stderr limit"),
                        }
                    };
                    Some(message)
                }
            }
        }
    }
}

struct LaunchCmd {
    program: String,
    arguments: Vec<String>,
}

struct ProcessMonitor {
    pid: i32,
    epoll: i32,
    stdin: i32,
    stdout: i32,
    stderr: i32,
    real_time_ms: u64,
    stdout_limit: u64,
    stderr_limit: u64,
    real_time_limit_ms: u64,
    stdout_written: u64,
    stderr_written: u64,
}

enum ProcessEvent {
    Finished(ExitResult),
    Timeout,
    StdoutLimit,
    StderrLimit,
    StdoutData(Vec<u8>),
    StderrData(Vec<u8>),
}

impl ProcessMonitor {
    pub fn new(
        stdin: i32,
        stdout: i32,
        stderr: i32,
        pid: i32,
        real_time_limit_sec: i32,
        stdout_limit_mb: i32,
        stderr_limit_mb: i32,
    ) -> ProcessMonitor {
        let epoll = unsafe {
            let epoll_fd = libc::epoll_create(1);
            let mut event_stdout = libc::epoll_event {
                events: libc::EPOLLIN as u32,
                u64: stdout as u64,
            };
            let mut event_stderr = libc::epoll_event {
                events: libc::EPOLLIN as u32,
                u64: stderr as u64,
            };
            libc::epoll_ctl(epoll_fd, libc::EPOLL_CTL_ADD, stdout, &mut event_stdout);
            libc::epoll_ctl(epoll_fd, libc::EPOLL_CTL_ADD, stderr, &mut event_stderr);

            epoll_fd
        };

        ProcessMonitor {
            pid,
            epoll,
            stdin,
            stdout,
            stderr,
            stdout_limit: stdout_limit_mb as u64 * 1024 * 1024,
            stderr_limit: stderr_limit_mb as u64 * 1024 * 1024,
            real_time_limit_ms: real_time_limit_sec as u64 * 1000,
            real_time_ms: 0,
            stdout_written: 0,
            stderr_written: 0,
        }
    }

    fn stop_event_processing(&mut self) {
        unsafe {
            libc::close(self.epoll);
            libc::close(self.stdin);
            libc::close(self.stdout);
            libc::close(self.stderr);
        }
    }

    fn kill(&mut self) {
        unsafe {
            libc::kill(self.pid, libc::SIGKILL);
        }
        self.stop_event_processing();
    }

    fn read_all_from_fd(fd: libc::c_int) -> Option<Vec<u8>> {
        let mut buf = Vec::<u8>::with_capacity(4096);
        buf.resize(4096, 0);
        let mut eagain = false;
        let mut result = Vec::<u8>::new();
        loop {
            let bytes_read = unsafe {
                libc::read(
                    fd,
                    buf.as_mut_ptr() as *mut libc::c_void,
                    buf.len() as libc::size_t,
                )
            };
            if bytes_read < 0 {
                // TODO check for error other than EAGAIN
                eagain = true;
                break;
            }
            if bytes_read == 0 {
                break;
            }
            let mut chunk = buf.clone();
            chunk.truncate(bytes_read as usize);
            result.append(&mut chunk);
        }

        if result.len() == 0 && !eagain {
            None
        } else {
            Some(result)
        }
    }

    pub fn next_event(&mut self) -> Option<ProcessEvent> {
        let mut epoll_event = libc::epoll_event { events: 0, u64: 0 };
        let events_count = unsafe { libc::epoll_wait(self.epoll, &mut epoll_event, 1, 1000) };
        if -1 == events_count {
            panic!("epoll_wait failed");
        }
        self.real_time_ms += 1000;
        if self.real_time_ms >= self.real_time_limit_ms && self.real_time_limit_ms > 0 {
            self.kill();
            return Some(ProcessEvent::Timeout);
        }
        if 0 == events_count {
            let mut waitstatus: libc::c_int = 0;
            unsafe {
                let waitpid_status = libc::waitpid(self.pid, &mut waitstatus, libc::WNOHANG);
                if waitpid_status != self.pid {
                    return None;
                }
                let exit_result = if libc::WIFSIGNALED(waitstatus) {
                    let signum = libc::WTERMSIG(waitstatus);
                    ExitResult::Killed(signum as u8)
                } else {
                    let status = libc::WEXITSTATUS(waitstatus);
                    ExitResult::Finished(status as u8)
                };
                self.stop_event_processing();
                return Some(ProcessEvent::Finished(exit_result));
            }
        }
        let fd = epoll_event.u64 as libc::c_int;
        if fd == self.stdout {
            let data = Self::read_all_from_fd(fd);
            if data.is_none() {
                unsafe {
                    libc::close(self.stdout);
                    return None;
                }
            }
            self.stdout_written += data.as_ref().unwrap().len() as u64;
            if self.stdout_written <= self.stdout_limit || self.stdout_limit == 0 {
                return Some(ProcessEvent::StdoutData(data.unwrap()));
            } else {
                self.kill();
                return Some(ProcessEvent::StdoutLimit);
            }
        }
        if fd == self.stderr {
            let data = Self::read_all_from_fd(fd);
            if data.is_none() {
                unsafe {
                    libc::close(self.stderr);
                    return None;
                }
            }
            self.stderr_written += data.as_ref().unwrap().len() as u64;
            if self.stderr_written <= self.stderr_limit || self.stderr_limit == 0 {
                return Some(ProcessEvent::StderrData(data.unwrap()));
            } else {
                self.kill();
                return Some(ProcessEvent::StderrLimit);
            }
        }

        panic!("unknown fd got in epoll_wait");
    }
}

pub struct Runner {
    logger: Logger,
    limits: Option<GradingLimits>,
    system_root: PathBuf,
    problem_root: PathBuf,
    submission_root: PathBuf,

    relative_workdir: PathBuf,
    exit_result: Option<ExitResult>,

    child: Option<ProcessMonitor>,

    stdout_sender: Option<UnboundedSender<Vec<u8>>>,
    stdout_receiver: Option<UnboundedReceiver<Vec<u8>>>,
    stderr_sender: Option<UnboundedSender<Vec<u8>>>,
    stderr_receiver: Option<UnboundedReceiver<Vec<u8>>>,
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
                let exit_result = Self::wait_for_finished_or_killed(child);
                Self::rethrow_exit_result(exit_result);
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
                let exit_result = Self::wait_for_finished_or_killed(child);
                Self::rethrow_exit_result(exit_result);
            }
            Child => {
                execvp(&filename, &arg_strings)?;
                println!("execvp failed");
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

    fn wait_for_finished_or_killed(pid: Pid) -> ExitResult {
        let result = loop {
            let wait_status: WaitStatus = waitpid(pid, None).unwrap();
            match wait_status {
                WaitStatus::Exited(_, exit_status) => {
                    break ExitResult::Finished(exit_status as u8);
                }
                WaitStatus::Signaled(_, signal, _) => {
                    break ExitResult::Killed(signal as u8);
                }
                _ => continue,
            }
        };
        return result;
    }

    // This function must be called only from child process!
    fn rethrow_exit_result(exit_result: ExitResult) {
        unsafe {
            match exit_result {
                ExitResult::Finished(status) => libc::_exit(status as i32),
                ExitResult::Killed(signum) => {
                    let _ = libc::raise(signum as i32);
                }
                _ => panic!("This case must not appear in child process"),
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

    pub fn start(&mut self, _program: &String, _arguments: &Vec<String>) -> Result<()> {
        let main_process = LaunchCmd {
            // program: "bash".into(),
            // arguments: vec!["-c".into(), "ulimit -a".into()],
            // arguments: vec![].into(),
            program: _program.clone(),
            arguments: _arguments.clone(),
        };

        let limits = self.limits.clone();
        let (mount_overlay_options, overlay_mergedir) = self.prepare_overlay_to_mount()?;
        let initial_cwd = self.relative_workdir.clone();

        let mut stdin_pipe = vec![-1, -1];
        let mut stdout_pipe = vec![-1, -1];
        let mut stderr_pipe = vec![-1, -1];

        unsafe { libc::pipe(stdin_pipe.as_mut_ptr()) };
        unsafe { libc::pipe2(stdout_pipe.as_mut_ptr(), libc::O_NONBLOCK) };
        unsafe { libc::pipe2(stderr_pipe.as_mut_ptr(), libc::O_NONBLOCK) };

        let (stdout_sender, stdout_receiver) = unbounded_channel();
        let (stderr_sender, stderr_receiver) = unbounded_channel();
        self.stdout_sender = Some(stdout_sender);
        self.stderr_sender = Some(stderr_sender);
        self.stdout_receiver = Some(stdout_receiver);
        self.stderr_receiver = Some(stderr_receiver);

        let fork_result = unsafe { fork()? };
        match fork_result {
            Parent { child } => {
                unsafe {
                    libc::close(stdin_pipe[0]);
                    libc::close(stdout_pipe[1]);
                    libc::close(stderr_pipe[1]);
                }
                let (real_time_limit_sec, stdout_limit_mb, stderr_limit_mb) = match limits {
                    None => (0, 0, 0),
                    Some(lim) => (
                        lim.real_time_limit_sec,
                        lim.stdout_size_limit_mb,
                        lim.stderr_size_limit_mb,
                    ),
                };
                let child_process = ProcessMonitor::new(
                    stdin_pipe[1],
                    stdout_pipe[0],
                    stderr_pipe[0],
                    child.as_raw(),
                    real_time_limit_sec,
                    stdout_limit_mb,
                    stderr_limit_mb,
                );
                self.child = Some(child_process);
            }
            Child => {
                unsafe {
                    libc::dup2(stdin_pipe[0], 0);
                    libc::dup2(stdout_pipe[1], 1);
                    libc::dup2(stderr_pipe[1], 2);
                    libc::close(stdin_pipe[0]);
                    libc::close(stdout_pipe[1]);
                    libc::close(stderr_pipe[1]);
                }
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

    pub fn process_events_until_finished(&mut self) -> Result<()> {
        if self.child.is_none() {
            return Err(anyhow!("Process not started"));
        }

        let child = self.child.as_mut().unwrap();

        loop {
            let event_option = child.next_event();
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

use anyhow::Result;
use prost::encoding::message;
use std::os::fd::{AsRawFd, OwnedFd, RawFd};

use nix::{sys, unistd};

use crate::runner::runner_impl::LogMessage;

use super::ExitResult;

pub struct ProcessMonitor {
    pid: unistd::Pid,
    epoll: sys::epoll::Epoll,
    stdin: Option<OwnedFd>,
    stdout: Option<OwnedFd>,
    stderr: Option<OwnedFd>,
    log: Option<OwnedFd>,
    real_time_ms: u64,
    stdout_limit: u64,
    stderr_limit: u64,
    real_time_limit_ms: u64,
    stdout_written: u64,
    stderr_written: u64,
    log_buffer: Vec<u8>,
}

pub enum ProcessEvent {
    Finished(ExitResult),
    Timeout,
    StdoutLimit,
    StderrLimit,
    StdoutData(Vec<u8>),
    StderrData(Vec<u8>),
    DebugMessage(String),
}

impl ProcessMonitor {
    pub fn new(
        stdin: OwnedFd,
        stdout: OwnedFd,
        stderr: OwnedFd,
        log: OwnedFd,
        pid: unistd::Pid,
        real_time_limit_sec: i32,
        stdout_limit_mb: i32,
        stderr_limit_mb: i32,
    ) -> Result<ProcessMonitor> {
        let epoll = sys::epoll::Epoll::new(sys::epoll::EpollCreateFlags::empty())?;
        epoll.add(
            &stdout,
            sys::epoll::EpollEvent::new(sys::epoll::EpollFlags::EPOLLIN, stdout.as_raw_fd() as u64),
        )?;
        epoll.add(
            &stderr,
            sys::epoll::EpollEvent::new(sys::epoll::EpollFlags::EPOLLIN, stderr.as_raw_fd() as u64),
        )?;
        epoll.add(
            &log,
            sys::epoll::EpollEvent::new(sys::epoll::EpollFlags::EPOLLIN, log.as_raw_fd() as u64),
        )?;

        let result = ProcessMonitor {
            pid,
            epoll,
            stdin: Some(stdin),
            stdout: Some(stdout),
            stderr: Some(stderr),
            log: Some(log),
            stdout_limit: stdout_limit_mb as u64 * 1024 * 1024,
            stderr_limit: stderr_limit_mb as u64 * 1024 * 1024,
            real_time_limit_ms: real_time_limit_sec as u64 * 1000,
            real_time_ms: 0,
            stdout_written: 0,
            stderr_written: 0,
            log_buffer: Vec::new(),
        };

        Ok(result)
    }

    fn stop_event_processing(&mut self) {
        self.stdin = None;
        self.stdout = None;
        self.stderr = None;
        self.log = None;
    }

    fn kill(&mut self) {
        let _ = sys::signal::kill(self.pid, sys::signal::SIGKILL);
        self.stop_event_processing();
    }

    fn read_all_from_fd(fd: i32) -> Option<Vec<u8>> {
        let mut buf = Vec::<u8>::with_capacity(4096);
        buf.resize(4096, 0);
        let mut result = Vec::<u8>::new();
        loop {
            let read_result = unistd::read(fd, buf.as_mut_slice());
            match read_result {
                Ok(bytes_read) => {
                    if bytes_read == 0 {
                        break;
                    } else {
                        let mut chunk = buf.clone();
                        chunk.truncate(bytes_read);
                        result.append(&mut chunk);
                    }
                }
                Err(_) => {
                    break;
                }
            }
        }

        if result.len() == 0 {
            None
        } else {
            Some(result)
        }
    }

    pub fn next_event(&mut self) -> Result<Option<ProcessEvent>> {
        let mut epoll_events = [sys::epoll::EpollEvent::empty()];
        let events_count = self.epoll.wait(&mut epoll_events, 1000)?;
        self.real_time_ms += 1000;
        if self.real_time_ms >= self.real_time_limit_ms && self.real_time_limit_ms > 0 {
            self.kill();
            return Ok(Some(ProcessEvent::Timeout));
        }
        if 0 == events_count {
            let mut wait_flags = sys::wait::WaitPidFlag::empty();
            wait_flags.insert(sys::wait::WaitPidFlag::WNOHANG);
            let wait_status = sys::wait::waitpid(self.pid, Some(wait_flags))?;
            if wait_status.pid() != Some(self.pid) {
                return Ok(None);
            }
            let exit_event = match wait_status {
                sys::wait::WaitStatus::Exited(_, status) => {
                    Some(ProcessEvent::Finished(ExitResult::Finished(status as u8)))
                }
                sys::wait::WaitStatus::Signaled(_, signal, _) => {
                    Some(ProcessEvent::Finished(ExitResult::Killed(signal as u8)))
                }
                _ => None,
            };
            self.stop_event_processing();
            return Ok(exit_event);
        }
        let raw_fd = epoll_events[0].data() as RawFd;
        if self.stdout.is_some()
            && raw_fd == self.stdout.as_ref().expect("stdout closed").as_raw_fd()
        {
            let data = Self::read_all_from_fd(raw_fd);
            if data.is_none() {
                self.stdout = None;
                return Ok(None);
            }
            self.stdout_written += data.as_ref().unwrap().len() as u64;
            if self.stdout_written <= self.stdout_limit || self.stdout_limit == 0 {
                return Ok(Some(ProcessEvent::StdoutData(data.unwrap())));
            } else {
                self.kill();
                return Ok(Some(ProcessEvent::StdoutLimit));
            }
        }
        if self.stderr.is_some()
            && raw_fd == self.stderr.as_ref().expect("stderr closed").as_raw_fd()
        {
            let data = Self::read_all_from_fd(raw_fd);
            if data.is_none() {
                self.stderr = None;
                return Ok(None);
            }
            self.stderr_written += data.as_ref().unwrap().len() as u64;
            if self.stderr_written <= self.stderr_limit || self.stderr_limit == 0 {
                return Ok(Some(ProcessEvent::StderrData(data.unwrap())));
            } else {
                self.kill();
                return Ok(Some(ProcessEvent::StderrLimit));
            }
        }
        if self.log.is_some() && raw_fd == self.log.as_ref().expect("log closed").as_raw_fd() {
            let data = Self::read_all_from_fd(raw_fd);
            if data.is_none() {
                self.log = None;
                return Ok(None);
            }
            self.log_buffer.append(&mut data.unwrap());
            let log_buffer_bytes = self.log_buffer.as_slice();
            let (message, tail_bytes) = postcard::take_from_bytes::<LogMessage>(log_buffer_bytes)?;
            self.log_buffer = Vec::from(tail_bytes);
            match message {
                LogMessage::Dbg(message) => return Ok(Some(ProcessEvent::DebugMessage(message))),
                LogMessage::Err(message) => {
                    return Err(anyhow!("Error in child process: {}", message))
                }
            }
        }

        panic!("unknown fd got in epoll_wait");
    }
}

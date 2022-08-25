package main

import (
	log "github.com/sirupsen/logrus"
	"io"
	"os"
	"sync"
	"syscall"
	"time"
)

type Service struct {
	InstanceName      string
	ServiceName       string
	Executable        string
	Status            ServiceStatus
	Error             string
	StartTime         int64
	RestartPolicy     RestartPolicyConf
	ShutdownTimeout   int
	LogFile           string
	PidFile           string
	SockFile          string
	CrashesSinceStart int

	mutex            sync.RWMutex
	shutdownComplete chan interface{}
	restartAttempts  int
	process          *os.Process
	stdout           *os.File
	stderr           *os.File
}

func NewService(instanceName, serviceName, executable, logFile, pidFile, sockFile string,
	initialStatus ServiceStatus,
	restartPolicy RestartPolicyConf,
	shutdownTimeout int,
) *Service {
	result := &Service{
		InstanceName:     instanceName,
		ServiceName:      serviceName,
		Executable:       executable,
		LogFile:          logFile,
		PidFile:          pidFile,
		SockFile:         sockFile,
		RestartPolicy:    restartPolicy,
		Status:           initialStatus,
		ShutdownTimeout:  shutdownTimeout,
		shutdownComplete: make(chan interface{}),
	}
	return result
}

func (service *Service) GetStatus() *ServiceStatusResponse {
	var uptime int64
	service.mutex.RLock()
	defer service.mutex.RUnlock()
	if service.Status == ServiceStatus_RUNNING {
		uptime = time.Now().Unix() - service.StartTime
	}
	pid := 0
	if service.process != nil {
		pid = service.process.Pid
	}
	return &ServiceStatusResponse{
		ServiceName:       service.ServiceName,
		Status:            service.Status,
		FailReason:        service.Error,
		Pid:               int32(pid),
		Uptime:            uptime,
		CrashesSinceStart: int32(service.CrashesSinceStart),
	}
}

func (service *Service) Start() {
	service.mutex.RLock()
	if service.Status == ServiceStatus_RUNNING {
		service.mutex.RUnlock()
		return
	}
	service.mutex.RUnlock()
	service.mutex.Lock()
	service.restartAttempts = 0
	service.CrashesSinceStart = 0
	service.mutex.Unlock()
	service.startProcess()
	if service.process != nil {
		service.mutex.RLock()
		log.Infof("started service %s@%s running with pid %v", service.ServiceName, service.InstanceName, service.process.Pid)
		service.mutex.RUnlock()
		go service.monitorProcess()
	} else {
		service.mutex.RLock()
		log.Warningf("cant start service %s@%s", service.ServiceName, service.InstanceName)
		service.mutex.RUnlock()
	}
}

func (service *Service) Stop() {
	service.mutex.RLock()
	if service.Status == ServiceStatus_STOPPED || service.Status == ServiceStatus_SHUTDOWN {
		service.mutex.RUnlock()
		return
	}
	service.mutex.RUnlock()
	service.stopProcess()
}

func (service *Service) checkFilesPermissions() {
	for {
		time.Sleep(time.Duration(250) * time.Millisecond)
		service.mutex.RLock()
		status := service.Status
		pidFile := service.PidFile
		logFile := service.LogFile
		sockFile := service.SockFile
		service.mutex.RUnlock()
		if status == ServiceStatus_SHUTDOWN || status == ServiceStatus_DISABLED || status == ServiceStatus_STOPPED {
			break
		}
		os.Chmod(pidFile, 0o664)
		os.Chmod(logFile, 0o660)
		os.Chmod(sockFile, 0o660)
	}
}

func (service *Service) monitorProcess() {
	go service.checkFilesPermissions()
	for {
		service.mutex.RLock()
		process := service.process
		service.mutex.RUnlock()
		processState, _ := process.Wait()

		service.mutex.RLock()
		serviceStatus := service.Status
		service.mutex.RUnlock()
		mustStopMonitor := true
		if serviceStatus == ServiceStatus_SHUTDOWN {
			log.Infof("service %s@%s shut down", service.ServiceName, service.InstanceName)
			service.cleanFiles()
			service.shutdownComplete <- 1
		} else if service.canRespawn() {
			service.mutex.Lock()
			stdoutData, _ := io.ReadAll(service.stdout)
			stderrData, _ := io.ReadAll(service.stderr)
			service.stdout.Close()
			service.stderr.Close()
			service.stdout = nil
			service.stderr = nil
			log.Warningf("service %s@%s dead with status %v, trying to restart",
				service.ServiceName, service.InstanceName, processState.ExitCode())
			if stdoutData != nil && len(stdoutData) > 0 {
				log.Warningf("stdout before death: %s", string(stdoutData))
			}
			if stderrData != nil && len(stderrData) > 0 {
				log.Warningf("stderr before death: %s", string(stderrData))
			}
			service.Status = ServiceStatus_RESPAWNING
			service.CrashesSinceStart++
			service.process = nil
			service.mutex.Unlock()
			service.cleanFiles()
			time.Sleep(time.Duration(service.RestartPolicy.RestartIntervalMs) * time.Millisecond)
			service.mutex.Lock()
			service.restartAttempts++
			service.mutex.Unlock()
			service.startProcess()
			mustStopMonitor = false
		} else {
			log.Warningf("service %s@%s dead with status %v",
				service.ServiceName, service.InstanceName, processState.ExitCode())
			service.mutex.Lock()
			service.Status = ServiceStatus_DEAD
			service.process = nil
			service.mutex.Unlock()
			service.cleanFiles()
		}
		if mustStopMonitor {
			break
		}
	}
}

func (service *Service) canRespawn() bool {
	uptime := time.Now().Unix() - service.StartTime
	canResetCounter := uptime >= int64(service.RestartPolicy.ResetAfterSec)
	if canResetCounter {
		service.mutex.Lock()
		service.restartAttempts = 0
		service.mutex.Unlock()
	}
	service.mutex.RLock()
	defer service.mutex.RUnlock()
	return service.restartAttempts < service.RestartPolicy.MaxTries
}

func (service *Service) startProcess() {
	executable, arguments := service.prepareArguments()
	fds := make([]*os.File, 3)
	service.mutex.Lock()
	service.stdout, fds[1], _ = os.Pipe()
	service.stderr, fds[2], _ = os.Pipe()
	service.mutex.Unlock()
	process, err := os.StartProcess(executable, arguments, &os.ProcAttr{
		Files: fds,
	})
	fds[1].Close()
	fds[2].Close()
	if err != nil {
		service.mutex.Lock()
		service.Status = ServiceStatus_FAILED
		service.Error = err.Error()
		service.process = nil
		service.stderr.Close()
		service.stderr.Close()
		service.stdout = nil
		service.stderr = nil
		log.Warningf("failed to start %s@%s: %v",
			service.ServiceName, service.InstanceName, err)
		service.mutex.Unlock()
	} else {
		service.mutex.Lock()
		service.Status = ServiceStatus_RUNNING
		service.process = process
		service.Error = ""
		service.StartTime = time.Now().Unix()
		service.mutex.Unlock()
	}
}

func (service *Service) cleanFiles() {
	service.mutex.RLock()
	if service.PidFile != "" {
		os.Remove(service.PidFile)
	}
	if service.SockFile != "" {
		os.Remove(service.SockFile)
	}
	service.mutex.RUnlock()
}

func (service *Service) stopProcess() {
	timeout := time.After(time.Duration(service.ShutdownTimeout) * time.Second)
	signalToSend := syscall.SIGTERM
	for {
		service.mutex.RLock()
		process := service.process
		service.mutex.RUnlock()
		if process == nil {
			log.Infof("service %s@%s is not running", service.ServiceName, service.InstanceName)
			break
		}
		if signalToSend == syscall.SIGTERM {
			log.Infof("terminating service %s@%s (pid=%v)", service.ServiceName, service.InstanceName, process.Pid)
		} else {
			log.Warningf("killing service %s@%s (pid=%v) after terminate attempt not finished within %v seconds",
				service.ServiceName, service.InstanceName, process.Pid, service.ShutdownTimeout,
			)
		}
		service.mutex.Lock()
		service.Status = ServiceStatus_SHUTDOWN
		service.mutex.Unlock()
		process.Signal(signalToSend)
		select {
		case <-service.shutdownComplete:
			service.mutex.Lock()
			service.Status = ServiceStatus_STOPPED
			service.process = nil
			service.mutex.Unlock()
			return
		case <-timeout:
			signalToSend = syscall.SIGKILL
		}
	}
}

func (service *Service) prepareArguments() (string, []string) {
	arguments := []string{
		service.Executable,
		"-P", service.PidFile,
		"-L", service.LogFile,
	}
	if service.InstanceName != "" {
		arguments = append(arguments, "-N", service.InstanceName)
	}
	return service.Executable, arguments
}

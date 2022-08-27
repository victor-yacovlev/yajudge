package main

import (
	log "github.com/sirupsen/logrus"
	"golang.org/x/exp/slices"
	"os"
	"path"
	"sort"
	"time"
)

type Instance struct {
	GlobalConfig *ServerConfig
	Config       *SupervisorConfig
	Grader       *Service
	Services     map[string]*Service

	exitHandler NotifyFunc
}

func NewInstance(globalConfig *ServerConfig, config *SupervisorConfig, exitHandler NotifyFunc) *Instance {
	var graderInitialStatus ServiceStatus
	if config.AutostartGrader {
		graderInitialStatus = ServiceStatus_STOPPED
	} else {
		graderInitialStatus = ServiceStatus_DISABLED
	}
	result := &Instance{
		GlobalConfig: globalConfig,
		Config:       config,
		Grader: NewService(
			config.InstanceName,
			"grader",
			globalConfig.ServiceExecutables["grader"],
			path.Join(globalConfig.LogFileDir, config.InstanceName, "grader.log"),
			path.Join(globalConfig.PidFileDir, config.InstanceName, "grader.pid"),
			"",
			graderInitialStatus,
			globalConfig.RestartPolicy,
			globalConfig.ShutdownTimeout,
			exitHandler,
		),
		exitHandler: exitHandler,
	}
	result.CreateServices()
	return result
}

func (instance *Instance) CreateServices() {
	os.MkdirAll(path.Join(instance.GlobalConfig.LogFileDir, instance.Config.InstanceName), 0o770)
	os.MkdirAll(path.Join(instance.GlobalConfig.PidFileDir, instance.Config.InstanceName), 0o770)
	masterServices := []string{"users", "content", "courses", "sessions", "submissions", "deadlines", "review", "progress"}
	instance.Services = make(map[string]*Service)
	for _, serviceName := range masterServices {
		var initialStatus ServiceStatus
		if slices.Contains(instance.Config.AutostartServices, serviceName) {
			initialStatus = ServiceStatus_STOPPED
		} else {
			initialStatus = ServiceStatus_DISABLED
		}
		service := NewService(
			instance.Config.InstanceName,
			serviceName,
			instance.GlobalConfig.ServiceExecutables[serviceName],
			path.Join(instance.GlobalConfig.LogFileDir, instance.Config.InstanceName, serviceName+".log"),
			path.Join(instance.GlobalConfig.PidFileDir, instance.Config.InstanceName, serviceName+".pid"),
			path.Join(instance.GlobalConfig.SockFileDir, instance.Config.InstanceName, serviceName+".sock"),
			initialStatus,
			instance.GlobalConfig.RestartPolicy,
			instance.GlobalConfig.ShutdownTimeout,
			instance.exitHandler,
		)
		instance.Services[serviceName] = service
	}
	if instance.Config.AutostartGrader {
		instance.Services["grader"] = instance.Grader
	}
}

func (instance *Instance) GetServiceStatuses() []*ServiceStatusResponse {
	result := make([]*ServiceStatusResponse, 0, len(instance.Services)+1)
	for _, service := range instance.Services {
		if service.ServiceName == "grader" {
			continue
		}
		status := service.GetStatus()
		result = append(result, status)
	}
	sort.Slice(result, func(i, j int) bool {
		return result[i].ServiceName < result[j].ServiceName
	})
	graderStatus := instance.Grader.GetStatus()
	result = append(result, graderStatus)
	return result
}

func (instance *Instance) Stop(names []string) {
	servicesToStop := make([]string, 0, len(instance.Services)+1)
	if len(names) > 0 {
		// stop specific services
		for _, serviceName := range names {
			if _, ok := instance.Services[serviceName]; ok && serviceName != "grader" {
				servicesToStop = append(servicesToStop, serviceName)
			}
		}
		// grader must be stopped first
		if slices.Contains(names, "grader") {
			servicesToStop = slices.Insert(servicesToStop, 0, "grader")
		}
	} else {
		// stop all running services
		servicesToStop = append(servicesToStop, "grader")
		for _, service := range instance.Services {
			if service.ServiceName != "grader" {
				servicesToStop = append(servicesToStop, service.ServiceName)
			}
		}
	}
	log.Infof("stopping instance %s services %v", instance.Config.InstanceName, servicesToStop)
	for _, serviceName := range servicesToStop {
		service := instance.Services[serviceName]
		if service != nil {
			service.Stop()
		}
	}
}

func (instance *Instance) Start(names []string) {
	instanceLogDir := path.Join(instance.GlobalConfig.LogFileDir, instance.Config.InstanceName)
	instancePidDir := path.Join(instance.GlobalConfig.PidFileName, instance.Config.InstanceName)
	sockDir := path.Dir(instance.GlobalConfig.GRPCSocketFileName)
	instanceSockDir := path.Join(sockDir, instance.Config.InstanceName)
	os.MkdirAll(instanceSockDir, 0o775)
	os.MkdirAll(instancePidDir, 0o775)
	os.MkdirAll(instanceLogDir, 0o775)
	os.Chmod(instanceSockDir, 0o775)
	os.Chmod(instanceLogDir, 0o775)
	os.Chmod(instancePidDir, 0o775)
	servicesToStart := make([]string, 0, len(instance.Services)+1)
	if len(names) > 0 {
		// start specific services
		for _, serviceName := range names {
			if _, ok := instance.Services[serviceName]; ok && serviceName != "grader" {
				servicesToStart = append(servicesToStart, serviceName)
			}
		}
		// grader must be started last
		if slices.Contains(names, "grader") {
			servicesToStart = append(servicesToStart, "grader")
		}
	} else {
		// start all config-enabled services
		for _, serviceName := range instance.Config.AutostartServices {
			servicesToStart = append(servicesToStart, serviceName)
		}
		if instance.Config.AutostartGrader {
			servicesToStart = append(servicesToStart, "grader")
		}
	}
	for index, serviceName := range servicesToStart {
		service := instance.Services[serviceName]
		if service.GetStatus().Status != ServiceStatus_RUNNING {
			if index > 0 {
				var timeoutMs int
				if serviceName == "grader" {
					timeoutMs = instance.GlobalConfig.ChainStartIntervals.Grader
				} else if serviceName == "webserver" || serviceName == "web" || serviceName == "grpcwebserver" {
					timeoutMs = instance.GlobalConfig.ChainStartIntervals.GrpcWebServer
				} else {
					timeoutMs = instance.GlobalConfig.ChainStartIntervals.Microservice
				}
				time.Sleep(time.Duration(timeoutMs) * time.Millisecond)
			}
			service.Start()
		}
	}
}

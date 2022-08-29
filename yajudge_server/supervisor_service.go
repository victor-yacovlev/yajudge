package main

import (
	"context"
	log "github.com/sirupsen/logrus"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"net"
	"os"
	"os/signal"
	"path"
	"strconv"
	"syscall"
	"time"
)

//go:generate protoc --go_out=. --go-grpc_out=. ./yajudge_supervisor.proto

type SupervisorService struct {
	SupervisorServer
	Config     *ServerConfig
	GRPCServer *grpc.Server
	Instances  map[string]*Instance
	WebServer  *Service
}

func NewSupervisorService(config *ServerConfig) *SupervisorService {
	var initialWebserverStatus ServiceStatus
	if config.AutostartGrpcWebServer {
		initialWebserverStatus = ServiceStatus_STOPPED
	} else {
		initialWebserverStatus = ServiceStatus_DISABLED
	}
	result := &SupervisorService{
		Config:    config,
		Instances: make(map[string]*Instance),
	}
	result.WebServer = NewService(
		"",
		"webserver",
		config.ServiceExecutables["webserver"],
		path.Join(config.LogFileDir, "webserver.log"),
		path.Join(config.PidFileDir, "webserver.pid"),
		"",
		initialWebserverStatus,
		config.RestartPolicy,
		config.ShutdownTimeout,
		result.NotifyOnServiceExit,
	)
	for _, instanceConfig := range config.Instances {
		result.Instances[instanceConfig.InstanceName] = NewInstance(config, instanceConfig, result.NotifyOnServiceExit)
	}
	return result
}

func (service *SupervisorService) GetSupervisorStatus(context.Context, *Empty) (*SupervisorStatusResponse, error) {
	result := &SupervisorStatusResponse{
		SupervisorPid: int32(os.Getpid()),
		InstanceNames: make([]string, 0, len(service.Config.Instances)),
	}
	for _, instanceConfig := range service.Config.Instances {
		result.InstanceNames = append(result.InstanceNames, instanceConfig.InstanceName)
	}
	return result, nil
}

func (service *SupervisorService) GetStatus(ctx context.Context, request *StatusRequest) (*StatusResponse, error) {
	if request.InstanceName == "web" || request.InstanceName == "webserver" || request.InstanceName == "grpcwebserver" {
		services := make([]*ServiceStatusResponse, 1)
		services[0] = service.WebServer.GetStatus()
		return &StatusResponse{
			InstanceName:    "webserver",
			ServiceStatuses: services,
		}, nil
	}
	instance, hasInstance := service.Instances[request.InstanceName]
	if !hasInstance {
		return nil, status.Errorf(codes.NotFound, "instance not found: %s", request.InstanceName)
	}
	serviceStatuses := instance.GetServiceStatuses()
	return &StatusResponse{
		InstanceName:    request.InstanceName,
		ServiceStatuses: serviceStatuses,
	}, nil
}

func (service *SupervisorService) Start(ctx context.Context, request *StartRequest) (*StatusResponse, error) {
	if request.InstanceName == "web" || request.InstanceName == "webserver" || request.InstanceName == "grpcwebserver" {
		service.WebServer.Start()
		services := make([]*ServiceStatusResponse, 1)
		services[0] = service.WebServer.GetStatus()
		return &StatusResponse{
			InstanceName:    "webserver",
			ServiceStatuses: services,
		}, nil
	}
	instance, instanceFound := service.Instances[request.InstanceName]
	if !instanceFound {
		return nil, status.Errorf(codes.NotFound, "instance %s not found", request.InstanceName)
	}

	// instance configuration might be changed so reload config file before start
	configFileName := instance.Config.FileName
	newConfig, err := LoadSupervisorConfig(configFileName)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "configuration failed in file %s: %v", configFileName, err)
	}
	instance.Config = newConfig

	instance.Start(request.ServiceNames)
	return &StatusResponse{
		InstanceName:    request.InstanceName,
		ServiceStatuses: instance.GetServiceStatuses(),
	}, nil
}

func (service *SupervisorService) Stop(ctx context.Context, request *StopRequest) (*StatusResponse, error) {
	if request.InstanceName == "web" || request.InstanceName == "webserver" || request.InstanceName == "grpcwebserver" {
		service.WebServer.Stop()
		services := make([]*ServiceStatusResponse, 1)
		services[0] = service.WebServer.GetStatus()
		return &StatusResponse{
			InstanceName:    "webserver",
			ServiceStatuses: services,
		}, nil
	}
	instance, instanceFound := service.Instances[request.InstanceName]
	if !instanceFound {
		return nil, status.Errorf(codes.NotFound, "instance %s not found", request.InstanceName)
	}
	instance.Stop(request.ServiceNames)
	return &StatusResponse{
		InstanceName:    request.InstanceName,
		ServiceStatuses: instance.GetServiceStatuses(),
	}, nil
}

func (service *SupervisorService) NotifyOnServiceExit(instanceName, serviceName string) {
	if serviceName == "grader" {
		// grader do not expose any socket, so it is not required to reconnect
		return
	}
	if service.WebServer != nil {
		log.Infof("sending SIGHUP to webserver due to one of services ")
		service.WebServer.SendSIGHUP()
	}
	for _, instance := range service.Instances {
		if instance != nil && instance.Config.InstanceName == instanceName {
			instance.NotifyOnServiceExit(serviceName)
		}
	}
}

func (service *SupervisorService) Main() {
	log.Infof("started supervisor with pid = %v", os.Getpid())
	service.createPIDFile()
	service.removeSocketFile()
	exitChan := make(chan interface{}, 1)
	signalsChan := make(chan os.Signal, 1)
	handleSignals := func() {
		signum := <-signalsChan
		exitChan <- signum
		close(exitChan)
	}
	go handleSignals()
	signal.Notify(signalsChan, syscall.SIGINT)
	signal.Notify(signalsChan, syscall.SIGTERM)
	service.GRPCServer = grpc.NewServer()
	RegisterSupervisorServer(service.GRPCServer, service)
	lis, err := net.Listen("unix", service.Config.GRPCSocketFileName)
	if err != nil {
		log.Fatalf("cant bind gRPC service: %v", err)
	}
	os.Chmod(service.Config.GRPCSocketFileName, 0o660)
	go service.GRPCServer.Serve(lis)
	time.AfterFunc(100*time.Millisecond, service.ProcessAutostart)
	<-exitChan
	log.Infof("shutting down supervisor and running services")
	service.WebServer.Stop()
	for _, instance := range service.Instances {
		instance.Stop([]string{})
	}
	service.removeSocketFile()
	service.removePIDFile()
	log.Infof("shutdown")
}

func (service *SupervisorService) ProcessAutostart() {
	for _, instance := range service.Instances {
		instance.Start([]string{})
	}
	if service.Config.AutostartGrpcWebServer {
		service.WebServer.Start()
	}
}

func (service *SupervisorService) createPIDFile() {
	pidDir := path.Dir(service.Config.PidFileName)
	if err := os.MkdirAll(pidDir, 0o775); err != nil {
		log.Errorf("cant create directory %s for PIDs: %v", pidDir, err)
		return
	}
	os.Chmod(pidDir, 0o775)
	myPid := strconv.Itoa(os.Getpid()) + "\n"
	pidFile, err := os.Create(service.Config.PidFileName)
	if err != nil {
		log.Errorf("cant create PID file %s: %v", service.Config.PidFileName, err)
		return
	}
	os.Chmod(service.Config.PidFileName, 0o664)
	pidFile.WriteString(myPid)
	pidFile.Close()
}

func (service *SupervisorService) removePIDFile() {
	if err := os.Remove(service.Config.PidFileName); err != nil {
		log.Errorf("cant remove PID file %s: %v", service.Config.PidFileName, err)
	}
}

func (service *SupervisorService) removeSocketFile() {
	if _, err := os.Stat(service.Config.GRPCSocketFileName); err != nil && os.IsNotExist(err) {
		return
	}
	if err := os.Remove(service.Config.GRPCSocketFileName); err != nil {
		log.Errorf("cant remove socket file %s: %v", service.Config.GRPCSocketFileName, err)
	}
}

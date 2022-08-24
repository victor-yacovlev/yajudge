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
	webServer := NewService(
		"",
		"webserver",
		config.ServiceExecutables["webserver"],
		path.Join(config.LogFileDir, "webserver.log"),
		path.Join(config.PidFileDir, "webserver.pid"),
		initialWebserverStatus,
		config.RestartPolicy,
		config.ShutdownTimeout,
	)
	result := &SupervisorService{
		Config:    config,
		Instances: make(map[string]*Instance),
		WebServer: webServer,
	}
	for _, instanceConfig := range config.Instances {
		result.Instances[instanceConfig.InstanceName] = NewInstance(config, instanceConfig)
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
	if err := os.MkdirAll(pidDir, 0640); err != nil {
		log.Errorf("cant create directory %s for PIDs: %v", pidDir, err)
		return
	}
	myPid := strconv.Itoa(os.Getpid()) + "\n"
	pidFile, err := os.Create(service.Config.PidFileName)
	if err != nil {
		log.Errorf("cant create PID file %s: %v", service.Config.PidFileName, err)
		return
	}
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
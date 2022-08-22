package main

import (
	"context"
	"fmt"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"log"
	"time"
)

//go:generate protoc --go_out=. --go-grpc_out=. -I ../../yajudge_server ../../yajudge_server/yajudge_supervisor.proto

type SupervisorConnection struct {
	Client     SupervisorClient
	Connection *grpc.ClientConn
}

func NewSupervisorConnection(socketFileName string) (*SupervisorConnection, error) {
	conn, err := grpc.Dial("unix://"+socketFileName, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		return nil, err
	}
	result := &SupervisorConnection{
		Connection: conn,
		Client:     NewSupervisorClient(conn),
	}
	return result, nil
}

func makeContext() context.Context {
	return context.Background() // TODO remove this line while debugged
	ctx, _ := context.WithTimeout(context.Background(), 1*time.Second)
	return ctx
}

func (conn *SupervisorConnection) ShowInstancesList() {
	response, err := conn.Client.GetSupervisorStatus(makeContext(), &Empty{})
	if err != nil {
		log.Fatal(err)
	}
	for _, instanceName := range response.InstanceNames {
		fmt.Printf("%s\n", instanceName)
	}
}

func (conn *SupervisorConnection) ShowStatus(instance string) {
	response, err := conn.Client.GetStatus(makeContext(), &StatusRequest{
		InstanceName: instance,
	})
	if err != nil {
		log.Fatal(err)
	}
	conn.PrintStatuses(response)
}

func (conn *SupervisorConnection) PrintStatuses(response *StatusResponse) {
	for _, serviceStatus := range response.ServiceStatuses {
		if serviceStatus.Status == ServiceStatus_RUNNING {
			fmt.Printf(" * %s [RUNNING][pid=%v, uptime %v seconds, crashed %v times]\n",
				serviceStatus.ServiceName, serviceStatus.Pid, serviceStatus.Uptime, serviceStatus.CrashesSinceStart,
			)
		} else if serviceStatus.Status == ServiceStatus_DISABLED {
			fmt.Printf(" * %s [DISABLED]\n", serviceStatus.ServiceName)
		} else if serviceStatus.Status == ServiceStatus_STOPPED {
			fmt.Printf(" * %s [STOPPED]\n", serviceStatus.ServiceName)
		} else if serviceStatus.Status == ServiceStatus_FAILED {
			fmt.Printf(" * %s [FAILED]: %s\n", serviceStatus.ServiceName, serviceStatus.FailReason)
		} else if serviceStatus.Status == ServiceStatus_DEAD {
			fmt.Printf(" * %s [DEAD][crashed %v times]\n",
				serviceStatus.ServiceName, serviceStatus.CrashesSinceStart,
			)
		}
	}
}

func (conn *SupervisorConnection) DoStart(instance string, services []string) {
	response, err := conn.Client.Start(context.Background(), &StartRequest{
		InstanceName: instance,
		ServiceNames: services,
	})
	if err != nil {
		log.Fatal(err)
	}
	conn.PrintStatuses(response)
}

func (conn *SupervisorConnection) DoStop(instance string, services []string) {
	response, err := conn.Client.Stop(context.Background(), &StopRequest{
		InstanceName: instance,
		ServiceNames: services,
	})
	if err != nil {
		log.Fatal(err)
	}
	conn.PrintStatuses(response)
}

func (conn *SupervisorConnection) DoRestart(instance string, services []string) {
	conn.DoStop(instance, services)
	conn.DoStart(instance, services)
}

package main

import (
	"context"
	"flag"
	"fmt"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"gopkg.in/yaml.v2"
	"io/ioutil"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"time"
	"yajudge_grader/grader_service"
)

func main() {
	configFileName := flag.String("config", "", "Configuration file path")
	if *configFileName == "" {
		*configFileName = FindConfigFile()
		if *configFileName != "" {
			fmt.Printf("Using config file %s\n", *configFileName)
		} else {
			fmt.Printf("Requires config file passed by 'config' option or placed in default location")
			os.Exit(127)
		}
	}
	config, err := ParseConfig(*configFileName)
	if err != nil {
		panic(err)
	}
	err = Serve(config)
	if err != nil {
		panic(err)
	}
}

func FindConfigFile() (res string) {
	binDir, _ := filepath.Abs(filepath.Dir(os.Args[0]))
	homeDir := os.Getenv("HOME")
	variants := []string{
		homeDir + "/.config/yajudge/grader.yaml",
		binDir + "/grader.yaml",
		"/etc/yajudge/grader.yaml",
	}
	for _, item := range variants {
		_, err := os.Stat(item)
		if err == nil {
			return item
		}
	}
	return ""
}

type GraderConfig struct {
	Rpc              grader_service.RpcConfig `yaml:"rpc"`
	WorkingDirectory string                   `yaml:"working_directory"`
	ExtraRuntimes    []string                 `yaml:"extra_runtimes"`
}

func ParseConfig(fileName string) (*GraderConfig, error) {
	_, err := os.Stat(fileName)
	if err != nil {
		return nil, err
	}
	confData, err := ioutil.ReadFile(fileName)
	if err != nil {
		return nil, err
	}
	conf := &GraderConfig{
		Rpc: grader_service.RpcConfig{
			Host: "localhost",
			Port: 9095,
		},
	}
	err = yaml.Unmarshal(confData, &conf)
	if err != nil {
		return nil, err
	}
	return conf, nil
}

func Serve(config *GraderConfig) (err error) {
	ctx, finish := context.WithCancel(context.Background())
	go func() {
		sigIntChan := make(chan os.Signal, 1)
		signal.Notify(sigIntChan, os.Interrupt)
		<-sigIntChan
		finish()
	}()
	service := grader_service.NewGraderService()
	err = service.ConnectToMasterService(config.Rpc)
	if err != nil {
		return err
	}
	service.WorkingDirectory = config.WorkingDirectory
	service.Worker = grader_service.NewWorker(config.ExtraRuntimes)
	restartTimeout, _ := time.ParseDuration("5s")
	for {
		err = service.ServeIncomingSubmissions(ctx)
		if err == nil {
			break
		}
		requireRestart := false
		if grpcStatus, isGrpcStatus := status.FromError(err); isGrpcStatus {
			_ = grpcStatus
			if grpcStatus.Code() == codes.Unavailable {
				requireRestart = true
			} else if grpcStatus.Code() == codes.Unauthenticated {
				// fatal error - check token value
				return fmt.Errorf("gRPC access fatal error. Check private auth token")
			}
		}
		log.Println(err)
		if requireRestart {
			time.Sleep(restartTimeout)
			service.ConnectToMasterService(config.Rpc)
			continue
		}
	}
	return err
}

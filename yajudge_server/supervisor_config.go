package main

import (
	"fmt"
	"github.com/ghodss/yaml"
	"os"
	"path"
	"runtime"
)

type RestartPolicyConf struct {
	MaxTries          int `yaml:"max_tries" json:"max_tries"`
	RestartIntervalMs int `yaml:"restart_interval_ms" json:"restart_interval_ms"`
	ResetAfterSec     int `yaml:"reset_after_sec" json:"reset_after_sec"`
}

type StartIntervalsConf struct {
	Grader        int `yaml:"grader" json:"grader"`
	GrpcWebServer int `yaml:"grpcwebserver" json:"grpcwebserver"`
	Microservice  int `yaml:"microservice" json:"microservice"`
}

type SupervisorConfig struct {
	FileName          string
	InstanceName      string
	AutostartServices []string `yaml:"autostart_services" json:"autostart_services"`
	AutostartGrader   bool     `yaml:"autostart_grader" json:"autostart_grader"`
	GraderBinPath     string
	ServicesBinPaths  map[string]string
}

type ServerConfig struct {
	FileName               string
	LogFileName            string
	PidFileName            string
	GRPCSocketFileName     string             `yaml:"grpc_socket_file_name" json:"grpc_socket_file_name"`
	AutostartGrpcWebServer bool               `yaml:"autostart_grpcwebserver" json:"autostart_grpcwebserver"`
	ChainStartIntervals    StartIntervalsConf `yaml:"chain_start_intervals" json:"chain_start_intervals"`
	RestartPolicy          RestartPolicyConf  `yaml:"restart_policy" json:"restart_policy"`
	ShutdownTimeout        int                `yaml:"shutdown_timeout_sec" json:"shutdown_timeout_sec"`
	Instances              []*SupervisorConfig
	ServiceExecutables     map[string]string
	LogFileDir             string
	PidFileDir             string
}

func (config *ServerConfig) ResolvePaths(yajudgeRootDir string) error {
	prodBinDir := path.Join(yajudgeRootDir, "bin")
	masterDevelBinDir := path.Join(yajudgeRootDir, "yajudge_master_services", "bin")
	graderDevelBinDir := path.Join(yajudgeRootDir, "yajudge_grader", "bin")
	webserverDevelBinDir := path.Join(yajudgeRootDir, "yajudge_grpcwebserver")
	masterServices := []string{"users", "content", "courses", "sessions", "submissions", "deadlines", "review", "progress"}
	var masterBinDir string
	var graderBinDir string
	var webserverBinDir string
	if stat, err := os.Stat(prodBinDir); err == nil && stat.IsDir() {
		masterBinDir = prodBinDir
		graderBinDir = prodBinDir
		webserverBinDir = prodBinDir
	} else {
		masterBinDir = masterDevelBinDir
		graderBinDir = graderDevelBinDir
		webserverBinDir = webserverDevelBinDir
	}
	graderExe := path.Join(graderBinDir, "yajudge-grader")
	webserverExe := path.Join(webserverBinDir, "yajudge-grpcwebserver")
	if runtime.GOOS == "windows" {
		graderExe += ".exe"
		webserverExe += ".exe"
	}
	if _, err := os.Stat(graderExe); err != nil {
		return fmt.Errorf("no executable found: %s", graderExe)
	}
	if _, err := os.Stat(webserverExe); err != nil {
		return fmt.Errorf("no executable found: %s", webserverExe)
	}
	config.ServiceExecutables = make(map[string]string)
	config.ServiceExecutables["grader"] = graderExe
	config.ServiceExecutables["webserver"] = webserverExe
	for _, service := range masterServices {
		serviceExe := path.Join(masterBinDir, "yajudge-service-"+service)
		if runtime.GOOS == "windows" {
			serviceExe += ".exe"
		}
		if _, err := os.Stat(serviceExe); err != nil {
			return fmt.Errorf("no executable found: %s", serviceExe)
		}
		config.ServiceExecutables[service] = serviceExe
	}
	config.LogFileDir = path.Join(yajudgeRootDir, "log")
	config.PidFileDir = path.Join(yajudgeRootDir, "pid")
	return nil
}

func LoadSupervisorConfig(fileName string) (*SupervisorConfig, error) {
	if _, err := os.Stat(fileName); os.IsNotExist(err) {
		return nil, fmt.Errorf("file not exists: %s", fileName)
	}
	yamlContent, err := os.ReadFile(fileName)
	if err != nil {
		return nil, fmt.Errorf("cant read %s: %v", fileName, err)
	}
	supervisorConfig := &SupervisorConfig{FileName: fileName}
	if err := yaml.Unmarshal(yamlContent, supervisorConfig); err != nil {
		return nil, fmt.Errorf("cant parse %s: %v", fileName, err)
	}
	return supervisorConfig, nil
}

func LoadServerConfig(fileName string) (*ServerConfig, error) {
	if _, err := os.Stat(fileName); os.IsNotExist(err) {
		return nil, fmt.Errorf("file not exists: %s", fileName)
	}
	yamlContent, err := os.ReadFile(fileName)
	if err != nil {
		return nil, fmt.Errorf("cant read %s: %v", fileName, err)
	}
	serverConfig := &ServerConfig{FileName: fileName}
	if err := yaml.Unmarshal(yamlContent, serverConfig); err != nil {
		return nil, fmt.Errorf("cant parse %s: %v", fileName, err)
	}
	configDir := path.Dir(fileName)
	serverConfig.Instances, err = LoadSupervisorConfigsFromSubdirectories(configDir)
	if err != nil {
		return nil, err
	}
	return serverConfig, nil
}

func LoadSupervisorConfigsFromSubdirectories(rootDirName string) ([]*SupervisorConfig, error) {
	if stat, err := os.Stat(rootDirName); os.IsNotExist(err) || !stat.IsDir() {
		return nil, fmt.Errorf("directory not exists: %s", rootDirName)
	}
	rootEntries, _ := os.ReadDir(rootDirName)
	result := make([]*SupervisorConfig, 0, len(rootEntries))
	for _, rootEntry := range rootEntries {
		if !rootEntry.IsDir() {
			continue
		}
		supervisorConfFile := path.Join(rootDirName, rootEntry.Name(), "supervisor.yaml")
		if _, err := os.Stat(supervisorConfFile); os.IsNotExist(err) {
			continue
		}
		supervisorConf, err := LoadSupervisorConfig(supervisorConfFile)
		if err != nil {
			return nil, err
		}
		supervisorConf.InstanceName = rootEntry.Name()
		result = append(result, supervisorConf)
	}
	return result, nil
}

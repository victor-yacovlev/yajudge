package main

import (
	"flag"
	"fmt"
	log "github.com/sirupsen/logrus"
	"os"
	"path"
)

func main() {
	configFileName := flag.String("C", "", "config file name")
	logFileName := flag.String("L", "", "log file name")
	pidFileName := flag.String("P", "", "PID file name")
	flag.Parse()
	if *configFileName == "" {
		defaultConfDir, err := resolveDefaultConfDir()
		if err != nil {
			log.Fatalf("%v", err)
		}
		*configFileName = path.Join(defaultConfDir, "server.yaml")
	}
	serverConfig, err := LoadServerConfig(*configFileName)
	if err != nil {
		log.Fatalf("%v", err)
	}
	yajudgeRootDir, err := resolveYajudgeRootDir()
	if err != nil {
		log.Fatalf("%v", err)
	}
	if err := serverConfig.ResolvePaths(yajudgeRootDir); err != nil {
		log.Fatalf("%v", err)
	}
	if *logFileName != "" {
		serverConfig.LogFileName = *logFileName
	}
	if *pidFileName != "" {
		serverConfig.PidFileName = *pidFileName
	}
	if serverConfig.LogFileName == "" {
		serverConfig.LogFileName = path.Join(yajudgeRootDir, "log", "supervisor.log")
	}
	if serverConfig.PidFileName == "" {
		serverConfig.PidFileName = path.Join(yajudgeRootDir, "pid", "supervisor.pid")
	}
	if serverConfig.GRPCSocketFileName == "" {
		serverConfig.GRPCSocketFileName = path.Join(yajudgeRootDir, "sock", "supervisor.sock")
	}
	if serverConfig.LogFileName != "stdout" {
		logFile, err := os.OpenFile(serverConfig.LogFileName, os.O_WRONLY|os.O_CREATE|os.O_APPEND, 0o660)
		if err != nil {
			log.Fatalf("cant create or open log file %s: %v", serverConfig.LogFileName, err)
		}
		log.SetOutput(logFile)
	}
	service := NewSupervisorService(serverConfig)
	service.Main()
}

func resolveYajudgeRootDir() (string, error) {
	serverExecutable, err := os.Executable()
	if err != nil {
		return "", fmt.Errorf("cant resolve yajudge directory: %v", err)
	}
	if stat, _ := os.Lstat(serverExecutable); stat.Mode()&os.ModeSymlink != 0 {
		serverExecutable, _ = os.Readlink(serverExecutable)
	}
	executableDir := path.Dir(serverExecutable)
	if !path.IsAbs(executableDir) {
		cwd, _ := os.Getwd()
		executableDir = path.Clean(path.Join(cwd, executableDir))
	}
	parentDir := path.Clean(path.Join(executableDir, ".."))
	return parentDir, nil
}

func resolveDefaultConfDir() (string, error) {
	yajudgeDir, err := resolveYajudgeRootDir()
	if err != nil {
		return "", err
	}
	yajudgeConfDir := path.Join(yajudgeDir, "conf")
	yajudgeConfDevelDir := path.Join(yajudgeDir, "conf-devel")
	if stat, err := os.Stat(yajudgeConfDir); err == nil && stat.IsDir() {
		return yajudgeConfDir, nil
	}
	if stat, err := os.Stat(yajudgeConfDevelDir); err == nil && stat.IsDir() {
		return yajudgeConfDevelDir, nil
	}
	return "", fmt.Errorf("no 'conf' or 'conf-devel' in %s", yajudgeDir)
}

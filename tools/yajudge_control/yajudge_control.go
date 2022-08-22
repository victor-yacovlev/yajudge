package main

import (
	"flag"
	"fmt"
	"github.com/ghodss/yaml"
	"log"
	"os"
	"path"
	"strings"
)

type ServerConfig struct {
	GRPCSocketFileName string `yaml:"grpc_socket_file_name" json:"grpc_socket_file_name"`
}

func main() {
	configFileName := flag.String("C", "", "config file name")
	flag.Parse()
	if *configFileName == "" {
		configDir, err := resolveDefaultConfDir()
		if err != nil {
			log.Fatal(err)
		}
		*configFileName = path.Join(configDir, "server.yaml")
	}
	serverConfig, err := loadServerConfig(*configFileName)
	if err != nil {
		log.Fatal(err)
	}
	socketFileName := serverConfig.GRPCSocketFileName
	yajudgeRootDir, err := resolveYajudgeRootDir()
	if err != nil {
		log.Fatal(err)
	}
	if socketFileName == "" {
		socketFileName = path.Join(yajudgeRootDir, "sock", "supervisor.sock")
	}
	connection, err := NewSupervisorConnection(socketFileName)
	if err != nil {
		log.Fatalf("cant connect to supervisor service. Ensure supervisor is running. Error: %v", err)
	}
	cmdLineArgs := flag.Args()
	if len(cmdLineArgs) < 1 {
		showHelpAndExit()
	}
	command := strings.ToLower(cmdLineArgs[0])
	commandArguments := cmdLineArgs[1:]
	processCommand(connection, command, commandArguments)
	connection.Connection.Close()
}

func showHelpAndExit() {
	message := `
Usage: yajudge-control COMMAND [INSTANCE] [SERVICES]
  COMMAND is one of:
    * list                          - show list of available instances
    * status  INSTANCE              - show status on instance
    * start   INSTANCE [SERVICES]   - start instance services
    * stop    INSTANCE [SERVICES]   - stop instance services
    * restart INSTANCE [SERVICES]   - restart instance services
  INSTANCE might be yajudge service instance of 'webserver'
  If SERVICES specified then start, stop or restart will affect only 
  specified services.
`
	fmt.Printf(message)
	os.Exit(127)
}

func processCommand(connection *SupervisorConnection, command string, arguments []string) {
	if command == "help" || command == "h" || command == "?" {
		showHelpAndExit()
		return
	}
	if command == "list" {
		connection.ShowInstancesList()
		return
	}
	if len(arguments) == 0 {
		log.Fatalf("requires instance name for this operation")
	}
	instanceName := arguments[0]
	restArguments := arguments[1:]
	if command == "status" {
		connection.ShowStatus(instanceName)
		return
	}
	if command == "start" {
		connection.DoStart(instanceName, restArguments)
		return
	}
	if command == "stop" {
		connection.DoStop(instanceName, restArguments)
		return
	}
	if command == "restart" {
		connection.DoRestart(instanceName, restArguments)
		return
	}
}

func loadServerConfig(fileName string) (*ServerConfig, error) {
	if _, err := os.Stat(fileName); os.IsNotExist(err) {
		return nil, fmt.Errorf("file not exists: %s", fileName)
	}
	yamlContent, err := os.ReadFile(fileName)
	if err != nil {
		return nil, fmt.Errorf("cant read %s: %v", fileName, err)
	}
	serverConfig := &ServerConfig{}
	if err := yaml.Unmarshal(yamlContent, serverConfig); err != nil {
		return nil, fmt.Errorf("cant parse %s: %v", fileName, err)
	}
	return serverConfig, nil
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
	parentDir := path.Clean(path.Join(executableDir, "../.."))
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

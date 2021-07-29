package main

//go:generate protoc --go_out=./core_service -I. service.proto
//go:generate protoc --go-grpc_out=./core_service -I. service.proto

import (
	"context"
	"flag"
	"fmt"
	"gopkg.in/yaml.v2"
	"io/ioutil"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"yajudge/service"
	"yajudge/ws_service"
)

func main() {
	configFileName := flag.String("config", "", "Configuration file path")
	initializeAndExit := flag.Bool("initialize-database", false, "Create empty database and exit")
	flag.Parse()
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
	if *initializeAndExit {
		err = InitializeEmptyDatabase(config)
	} else {
		err = Serve(config)
	}
	if err != nil {
		panic(err)
	}
}

type DatabaseConfig struct {
	Host				string `yaml:"host"`
	Port				uint16 `yaml:"port"`
	Name				string `yaml:"name"`
	User				string `yaml:"user"`
	Password			string `yaml:"password"`
}

type RpcConfig struct {
	Host				string `yaml:"host"`
	Port				uint16 `yaml:"port"`
	PublicToken			string `yaml:"public_token"`
	PrivateToken		string `yaml:"private_token"`
}

type WebConfig struct {
	Host			string `yaml:"host"`
	Port			uint16 `yaml:"port"`
	Root			string `yaml:"root"`
	StaticDir		string `yaml:"static_dir"`
	WsApi			string `yaml:"ws_api"`
}

type LocationsConfig struct {
	CoursesRoot		string `yaml:"courses_root"`
	WebStaticRoot	string `yaml:"web_static_root"`
}

type YajudgeServerConfig struct {
	Database  		DatabaseConfig  `yaml:"database"`
	Rpc       		RpcConfig       `yaml:"rpc"`
	Web       		WebConfig       `yaml:"web"`
	Locations 		LocationsConfig `yaml:"locations"`
}

func ParseConfig(fileName string) (*YajudgeServerConfig, error) {
	_, err := os.Stat(fileName)
	if err != nil {
		return nil, err
	}
	confData, err := ioutil.ReadFile(fileName)
	if err != nil {
		return nil, err
	}
	conf := &YajudgeServerConfig{
		Database: DatabaseConfig{
			Host: "localhost",
			Port: 5432,
		},
		Rpc:      RpcConfig{
			Host: "localhost",
			Port: 9095,
		},
		Web:      WebConfig{
			Host: "localhost",
			Port: 8080,
			Root: "/",
			WsApi: "/api-ws",
		},
	}
	err = yaml.Unmarshal(confData, &conf)
	if err != nil {
		return nil, err
	}
	return conf, nil
}

func Serve(config *YajudgeServerConfig) error {
	ctx, finish := context.WithCancel(context.Background())
	defer finish()
	mux := http.DefaultServeMux
	listenAddr := config.Web.Host + ":" + strconv.Itoa(int(config.Web.Port))
	srv := http.Server { Handler: mux, Addr: listenAddr }
	defer srv.Shutdown(context.Background())

	signalsChan := make(chan interface{})
	go func() {
		sigIntChan := make(chan os.Signal, 1)
		signal.Notify(sigIntChan, os.Interrupt)
		<- sigIntChan
		close(signalsChan)
	}()
	defer finish()

	rpcAddr := config.Rpc.Host + ":" + strconv.Itoa(int(config.Rpc.Port))
	rpcServices, err := core_service.StartServices(
		ctx,
		rpcAddr,
		config.Rpc.PublicToken, config.Rpc.PrivateToken, core_service.DatabaseProperties{
			Engine:   "postgres",
			Host:     config.Database.Host,
			Port:     config.Database.Port,
			User:     config.Database.User,
			Password: config.Database.Password,
			DBName:   config.Database.Name,
			SSLMode:  "disable",
		},
		config.Locations.CoursesRoot,
	)
	_ = rpcServices
	if err != nil {
		return err
	}

	ws, err := ws_service.StartWebsocketHttpHandler(
		config.Rpc.PublicToken,
		rpcAddr,
		)
	if err != nil {
		return err
	}

	mux.Handle(config.Web.WsApi, ws)
	mux.Handle(config.Web.Root,
		http.StripPrefix(config.Web.Root, http.FileServer(http.Dir(config.Web.StaticDir))))

	err = srv.ListenAndServe();
	if err != nil {
		return err
	}
	<- signalsChan
	return nil
}

func InitializeEmptyDatabase(config *YajudgeServerConfig) error {
	ctx, finish := context.WithCancel(context.Background())
	defer finish()
	rpcServices, err := core_service.StartServices(
		ctx,
		config.Rpc.Host + ":" + string(config.Rpc.Port),
		config.Rpc.PublicToken, config.Rpc.PrivateToken, core_service.DatabaseProperties{
			Engine:   "postgres",
			Host:     config.Database.Host,
			Port:     config.Database.Port,
			User:     config.Database.User,
			Password: config.Database.Password,
			DBName:   config.Database.Name,
			SSLMode:  "disable",
		},
		config.Locations.CoursesRoot,
	)
	if err != nil {
		return err
	}
	rpcServices.CreateEmptyDatabase()
	return nil
}

func FindConfigFile() (res string) {
	binDir, _ := filepath.Abs(filepath.Dir(os.Args[0]))
	homeDir := os.Getenv("HOME")
	variants := []string{
		homeDir + "/.config/yajudge/server.yaml",
		binDir + "/server.yaml",
		"/etc/yajudge/server.yaml",
	}
	for _, item := range variants {
		_, err := os.Stat(item)
		if err == nil {
			return item
		}
	}
	return ""
}
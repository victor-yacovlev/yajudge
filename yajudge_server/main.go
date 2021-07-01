package main

import (
	"context"
	"flag"
	"fmt"
	"gopkg.in/gcfg.v1"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
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
	Host				string
	Port				uint16
	Name				string
	User				string
	Password			string
}

type RpcConfig struct {
	ListenAddr			string
	PublicAuthToken		string
	PrivateAuthToken	string
}

type WebConfig struct {
	ListenAddr		string
	ContentRootDir	string
	ContentPrefix	string
	ApiPrefix		string
}

type LogConfig struct {
	ErrorFile		string
	AccessFile		string
	RpcFile			string
}

type YajudgeServerConfig struct {
	Database		DatabaseConfig
	Rpc				RpcConfig
	Web				WebConfig
	Log				LogConfig
}

func ParseConfig(fileName string) (*YajudgeServerConfig, error) {
	_, err := os.Stat(fileName)
	if err != nil {
		return nil, err
	}
	conf := &YajudgeServerConfig{
		Database: DatabaseConfig{
			Host: "localhost",
			Port: 5432,
		},
		Rpc:      RpcConfig{
			ListenAddr: ":9095",
		},
		Web:      WebConfig{
			ListenAddr: ":8080",
			ContentPrefix: "/",
			ApiPrefix: "/api-ws",
		},
		Log: 	  LogConfig{

		},
	}
	err = gcfg.ReadFileInto(conf, fileName)
	if err != nil {
		return nil, err
	}
	return conf, nil
}

func Serve(config *YajudgeServerConfig) error {
	ctx, finish := context.WithCancel(context.Background())
	defer finish()
	mux := http.DefaultServeMux
	srv := http.Server { Handler: mux, Addr: config.Web.ListenAddr }
	defer srv.Shutdown(context.Background())

	signalsChan := make(chan interface{})
	go func() {
		sigIntChan := make(chan os.Signal, 1)
		signal.Notify(sigIntChan, os.Interrupt)
		<- sigIntChan
		close(signalsChan)
	}()
	defer finish()

	rpcServices, err := core_service.StartServices(ctx, config.Rpc.ListenAddr,
		config.Rpc.PublicAuthToken, config.Rpc.PrivateAuthToken, core_service.DatabaseProperties{
			Engine:   "postgres",
			Host:     config.Database.Host,
			Port:     config.Database.Port,
			User:     config.Database.User,
			Password: config.Database.Password,
			DBName:   config.Database.Name,
			SSLMode:  "disable",
		})
	_ = rpcServices
	if err != nil {
		return err
	}

	ws, err := ws_service.StartWebsocketHttpHandler(config.Rpc.PublicAuthToken, config.Rpc.ListenAddr)
	if err != nil {
		return err
	}

	mux.Handle(config.Web.ApiPrefix, ws)
	mux.Handle(config.Web.ContentPrefix,
		http.StripPrefix(config.Web.ContentPrefix, http.FileServer(http.Dir(config.Web.ContentRootDir))))

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
	rpcServices, err := core_service.StartServices(ctx, config.Rpc.ListenAddr,
		config.Rpc.PublicAuthToken, config.Rpc.PrivateAuthToken, core_service.DatabaseProperties{
			Engine:   "postgres",
			Host:     config.Database.Host,
			Port:     config.Database.Port,
			User:     config.Database.User,
			Password: config.Database.Password,
			DBName:   config.Database.Name,
			SSLMode:  "disable",
		})
	if err != nil {
		return err
	}
	rpcServices.CreateEmptyDatabase()
	rpcServices.CreateStandardRoles()
	return nil
}

func FindConfigFile() (res string) {
	binDir, _ := filepath.Abs(filepath.Dir(os.Args[0]))
	variants := []string{
		binDir + "/yajudge-server.ini",
		"/etc/yajudge-server.ini",
	}
	for _, item := range variants {
		_, err := os.Stat(binDir + "/yajudge-server.ini")
		if err == nil {
			return item
		}
	}
	return ""
}
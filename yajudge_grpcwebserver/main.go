package main

import (
	"crypto/tls"
	"flag"
	"fmt"
	log "github.com/sirupsen/logrus"
	"golang.org/x/net/http2"
	"golang.org/x/net/http2/h2c"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"time"
)

func main() {
	configFileName := flag.String("C", "", "config file name")
	logFileName := flag.String("L", "", "log file name")
	pidFileName := flag.String("P", "", "PID file name")
	flag.Parse()
	if configFileName == nil || *configFileName == "" {
		log.Fatalf("Requires config file passed by -C option")
	}
	config, err := ParseWebServerConfig(*configFileName)
	if err != nil {
		log.Fatalf("Cant parse config file %s: %v", *configFileName, err)
	}
	if logFileName != nil && *logFileName != "" {
		config.Service.LogFile = *logFileName
	}
	if pidFileName != nil && *pidFileName != "" {
		config.Service.PidFile = *pidFileName
	}
	initializeLogger(config.Service.LogFile)
	createPIDFile(config.Service.PidFile)
	httpListener, httpsListener, err := createListeners(config.Hosts, config.Web)
	if err != nil {
		log.Fatalf("cant create network listeners: %v", err)
	}
	yajudgeStaticWebHandler, err := NewStaticHandler(config.Web)
	if err != nil {
		log.Fatalf("cant create static handler: %v", err)
	}
	handler := NewServerHandler()
	for name, hostConfig := range config.Hosts {
		handler.Hosts[name] = NewHostInstance(name, hostConfig, yajudgeStaticWebHandler, config.Web.HttpsPort)
	}
	http2Server := &http2.Server{
		IdleTimeout: 15 * time.Minute,
	}
	http1Server := &http.Server{
		Handler: h2c.NewHandler(handler, http2Server),
	}
	err = http2.ConfigureServer(http1Server, http2Server)
	if err != nil {
		log.Fatalf("cant create HTTP/2 server: %v", err)
	}
	go http1Server.Serve(httpListener)
	if httpsListener != nil {
		go http1Server.Serve(httpsListener)
	}
	signalsChan := make(chan interface{})
	handleSignal := func(signum os.Signal) {
		signalChan := make(chan os.Signal, 1)
		signal.Notify(signalChan, signum)
		<-signalsChan
		close(signalsChan)
	}
	go handleSignal(os.Interrupt)
	<-signalsChan
	removePIDFile(config.Service.PidFile)
}

func initializeLogger(logFileName string) {
	if logFileName != "" && logFileName != "stdout" {
		parts := strings.Split(logFileName, "/")
		dirParts := parts[0 : len(parts)-1]
		dirPath := strings.Join(dirParts, "/")
		if err := os.MkdirAll(dirPath, 0770); err != nil {
			log.Fatalf("cant create directory for log file %s: %v", logFileName, err)
		}
		file, err := os.OpenFile(logFileName, os.O_WRONLY|os.O_CREATE|os.O_APPEND, 0660)
		if err != nil {
			log.Fatalf("cant create or open log file %s: %v", logFileName, err)
		}
		log.SetOutput(file)
	}
}

func createPIDFile(pidFileName string) {
	if pidFileName != "" {
		parts := strings.Split(pidFileName, "/")
		dirParts := parts[0 : len(parts)-1]
		dirPath := strings.Join(dirParts, "/")
		if err := os.MkdirAll(dirPath, 0770); err != nil {
			log.Warningf("cant create directory for PID file %s: %v", pidFileName, err)
			return
		}
		file, err := os.OpenFile(pidFileName, os.O_WRONLY|os.O_CREATE, 0660)
		if err != nil {
			log.Warningf("cant create or open log file %s: %v", pidFileName, err)
			return
		}
		file.WriteString(fmt.Sprintf("%d\n", os.Getpid()))
		file.Close()
	}
}

func removePIDFile(pidFileName string) {
	if pidFileName != "" {
		os.Remove(pidFileName)
	}
}

func createListeners(hosts map[string]HostConfig, webConfig WebConfig) (net.Listener, net.Listener, error) {
	tlsConfig, err := createTlsConfig(hosts)
	if err != nil {
		return nil, nil, err
	}
	var httpListener, httpsListener net.Listener
	httpListener, err = net.Listen("tcp", ":"+strconv.Itoa(webConfig.HttpPort))
	if err != nil {
		return nil, nil, err
	}
	if tlsConfig != nil && webConfig.HttpsPort != 0 {
		httpsListener, err = tls.Listen("tcp", ":"+strconv.Itoa(webConfig.HttpsPort), tlsConfig)
		if err != nil {
			return nil, nil, err
		}
	}
	return httpListener, httpsListener, nil
}

func createTlsConfig(hosts map[string]HostConfig) (*tls.Config, error) {
	result := &tls.Config{
		NextProtos:   []string{"h2"},
		Certificates: make([]tls.Certificate, 0),
	}
	useSsl := false
	for name, host := range hosts {
		if host.SslCertificate != "" && host.SslCertificateKey != "" {
			cert, err := tls.LoadX509KeyPair(host.SslCertificate, host.SslCertificateKey)
			if err != nil {
				return nil, fmt.Errorf("cant read SSL certificate or key for host %s: %v", name, err)
			}
			result.Certificates = append(result.Certificates, cert)
			useSsl = true
		}
	}
	if useSsl {
		result.BuildNameToCertificate()
		return result, nil
	} else {
		return nil, nil
	}
}

package main

import (
	"github.com/ghodss/yaml"
	"io/ioutil"
	"os"
)

type HostConfig struct {
	ProxyPass         string `yaml:"proxy_pass" json:"proxy_pass"`
	MasterHost        string `yaml:"master_host" json:"master_host"`
	MasterPort        int    `yaml:"master_port" json:"master_port"`
	SslCertificate    string `yaml:"ssl_certificate" json:"ssl_certificate"`
	SslCertificateKey string `yaml:"ssl_certificate_key" json:"ssl_certificate_key"`
}

type ServiceConfig struct {
	LogFile string `yaml:"log_file" json:"log_file"`
	PidFile string `yaml:"pid_file" json:"pid_file"`
}

type WebConfig struct {
	HttpPort       int    `yaml:"http_port" json:"http_port"`
	HttpsPort      int    `yaml:"https_port" json:"https_port"`
	YajudgeWebRoot string `yaml:"yajudge_web_root" json:"yajudge_web_root"`
}

type WebServerConfig struct {
	Service ServiceConfig         `yaml:"service" json:"service"`
	Web     WebConfig             `yaml:"web" json:"web"`
	Hosts   map[string]HostConfig `yaml:"hosts" json:"hosts"`
}

func ParseWebServerConfig(fileName string) (*WebServerConfig, error) {
	if _, err := os.Stat(fileName); err != nil {
		return nil, err
	}
	confData, err := ioutil.ReadFile(fileName)
	if err != nil {
		return nil, err
	}
	var config WebServerConfig
	if err := yaml.Unmarshal(confData, &config); err != nil {
		return nil, err
	}
	return &config, nil
}

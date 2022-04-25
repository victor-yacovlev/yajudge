package main

import (
	"fmt"
	"github.com/ghodss/yaml"
	"io/ioutil"
	"os"
	"strings"
)

type SiteConfig struct {
	HostName                   string `yaml:"host_name" json:"host_name"`
	ProxyPass                  string `yaml:"proxy_pass" json:"proxy_pass"`
	GrpcBackendHost            string `yaml:"grpc_backend_host" json:"grpc_backend_host"`
	GrpcBackendPort            int    `yaml:"grpc_backend_port" json:"grpc_backend_port"`
	SslCertificate             string `yaml:"ssl_certificate" json:"ssl_certificate"`
	SslCertificateKey          string `yaml:"ssl_certificate_key" json:"ssl_certificate_key"`
	WebAppStaticRoot           string `yaml:"web_app_static_root" json:"web_app_static_root"`
	WebAppIndexFile            string `yaml:"web_app_index_file" json:"web_app_index_file"`
	WebAppDisableSPANavigation bool   `yaml:"web_app_disable_spa_navigation" json:"web_app_disable_spa_navigation"`
}

type ServiceConfig struct {
	LogFile string `yaml:"log_file" json:"log_file"`
	PidFile string `yaml:"pid_file" json:"pid_file"`
}

type ListenConfig struct {
	BindAddress string `yaml:"bind_address" json:"bind_address"`
	HttpPort    int    `yaml:"http_port" json:"http_port"`
	HttpsPort   int    `yaml:"https_port" json:"https_port"`
}

type WebServerConfig struct {
	Service            ServiceConfig          `yaml:"service" json:"service"`
	Listen             ListenConfig           `yaml:"listen" json:"listen"`
	Sites              map[string]*SiteConfig `yaml:"sites" json:"sites"`
	SitesConfDirectory string                 `yaml:"sites_conf_directory" json:"sites_conf_directory"`
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
	if config.Sites == nil {
		config.Sites = make(map[string]*SiteConfig)
	}
	if config.SitesConfDirectory != "" {
		dirEntries, _ := os.ReadDir(config.SitesConfDirectory)
		if dirEntries != nil {
			for _, dirEntry := range dirEntries {
				siteConfFileName := config.SitesConfDirectory + "/" + dirEntry.Name()
				siteConf, err := ParseSiteConfig(siteConfFileName)
				if err != nil {
					return nil, fmt.Errorf("cant parse site config %s: %v", siteConfFileName, err)
				}
				config.Sites[siteConf.HostName] = siteConf
			}
		}
	}
	if len(config.Sites) == 0 {
		return nil, fmt.Errorf("no any sites defined by confiration")
	}
	if config.Listen.BindAddress == "" || config.Listen.BindAddress == "any" {
		config.Listen.BindAddress = "0.0.0.0"
	}
	return &config, nil
}

func ParseSiteConfig(fileName string) (*SiteConfig, error) {
	if _, err := os.Stat(fileName); err != nil {
		return nil, err
	}
	confData, err := ioutil.ReadFile(fileName)
	if err != nil {
		return nil, err
	}
	var config SiteConfig
	if err := yaml.Unmarshal(confData, &config); err != nil {
		return nil, err
	}
	if config.HostName == "" {
		return nil, fmt.Errorf("does not contains 'host_name'", fileName)
	}
	if config.ProxyPass != "" && config.WebAppStaticRoot != "" {
		msg := fmt.Errorf("must have either non-empty 'wep_app_static_root' or 'proxy_pass' but not both")
		return nil, msg
	}
	if config.ProxyPass != "" &&
		!strings.HasPrefix(config.ProxyPass, "http://") &&
		!strings.HasPrefix(config.ProxyPass, "https://") {
		config.ProxyPass = "http://" + config.ProxyPass
	}
	if config.WebAppIndexFile == "" {
		config.WebAppIndexFile = "/index.html"
	}
	return &config, nil
}

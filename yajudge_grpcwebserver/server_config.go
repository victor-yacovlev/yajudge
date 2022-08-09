package main

import (
	"fmt"
	"github.com/ghodss/yaml"
	"io/ioutil"
	"net/url"
	"os"
	"path"
	"strings"
)

type EndpointConfig struct {
	ServiceName string
	ServiceURL  *url.URL
}

type SiteConfig struct {
	HostName                   string `yaml:"host_name" json:"host_name"`
	ProxyPass                  string `yaml:"proxy_pass" json:"proxy_pass"`
	Endpoints                  []*EndpointConfig
	SslCertificate             string `yaml:"ssl_certificate" json:"ssl_certificate"`
	SslCertificateKey          string `yaml:"ssl_certificate_key" json:"ssl_certificate_key"`
	WebAppStaticRoot           string `yaml:"web_app_static_root" json:"web_app_static_root"`
	WebAppIndexFile            string `yaml:"web_app_index_file" json:"web_app_index_file"`
	WebAppDisableSPANavigation bool   `yaml:"web_app_disable_spa_navigation" json:"web_app_disable_spa_navigation"`
	WebAppStaticMaxAge         int    `yaml:"web_app_static_max_age" json:"web_app_static_max_age"`
	StaticReloadInterval       int    `yaml:"static_reload_interval" json:"static_reload_interval"`
	EndpointsFileName          string `yaml:"grpc_endpoints" json:"grpc_endpoints"`
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
	if config.WebAppStaticMaxAge == 0 {
		config.WebAppStaticMaxAge = 31536000
	} else {
		config.WebAppStaticMaxAge = config.WebAppStaticMaxAge * 60 * 60
	}
	if config.StaticReloadInterval == 0 {
		config.StaticReloadInterval = 600
	}
	endpointLocalFileName := config.EndpointsFileName
	_ = endpointLocalFileName
	confDir, _ := path.Split(fileName)
	endpointFileName := path.Join(confDir, endpointLocalFileName)
	endpointConfData, err := ioutil.ReadFile(endpointFileName)
	if err != nil {
		return nil, err
	}
	var endpoints map[string]string
	err = yaml.Unmarshal(endpointConfData, &endpoints)
	if err != nil {
		return nil, err
	}
	config.Endpoints = make([]*EndpointConfig, 0)
	for endpointName, endpointLink := range endpoints {
		endpointUrl, err := url.Parse(endpointLink)
		if err != nil {
			return nil, err
		}
		config.Endpoints = append(config.Endpoints, &EndpointConfig{
			ServiceName: endpointName,
			ServiceURL:  endpointUrl,
		})
	}
	return &config, nil
}

func ParseEndpointsConfig(fileName string) {

}

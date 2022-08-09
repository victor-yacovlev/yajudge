package main

import (
	"fmt"
	"github.com/improbable-eng/grpc-web/go/grpcweb"
	"github.com/mwitkow/grpc-proxy/proxy"
	log "github.com/sirupsen/logrus"
	"golang.org/x/net/context"
	"google.golang.org/grpc"
	"google.golang.org/grpc/metadata"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
)

type GrpcEndpoint struct {
	grpcServer    *grpc.Server
	grpcWebServer *grpcweb.WrappedGrpcServer
	grpcClient    *grpc.ClientConn
	target        string
}

type Site struct {
	name              string
	config            *SiteConfig
	staticHandler     *StaticHandler
	httpsRedirectBase string
	proxyPassURL      *url.URL
	//grpcServer        *grpc.Server
	//grpcWebServer     *grpcweb.WrappedGrpcServer
	//grpcClient        *grpc.ClientConn
	endpoints map[string]*GrpcEndpoint
}

type ServerHandler struct {
	Sites map[string]*Site
}

func (s *ServerHandler) ServeHTTP(writer http.ResponseWriter, request *http.Request) {
	parts := strings.Split(request.Host, ":")
	hostName := parts[0]
	if hostName == "localhost" {
		// might be proxied so check for Origin header
		origin := request.Header.Get("Origin")
		originUrl, _ := url.Parse(origin)
		if originUrl != nil && originUrl.Host != "" {
			parts = strings.Split(originUrl.Host, ":")
			hostName = parts[0]
		}
	}
	host, found := s.Sites[hostName]
	if !found {
		msg := fmt.Sprintf("no host %s configured", hostName)
		log.Warningf("%s", msg)
		http.Error(writer, msg, 404)
		return
	}
	host.Serve(writer, request)
}

func NewServerHandler() *ServerHandler {
	return &ServerHandler{
		Sites: make(map[string]*Site, 0),
	}
}

func NewHostInstance(name string, config *SiteConfig, httpsPort int) (*Site, error) {
	httpsRedirectHost := ""
	if httpsPort != 0 && config.SslCertificate != "" && config.SslCertificateKey != "" {
		httpsRedirectHost = name
		if httpsPort != 443 {
			httpsRedirectHost += ":" + strconv.Itoa(httpsPort)
		}
	}
	var proxyPassURL *url.URL
	if config.ProxyPass != "" {
		proxyPassURL, _ = url.Parse(config.ProxyPass)
	}
	var staticHandler *StaticHandler
	if config.WebAppStaticRoot != "" {
		var err error
		staticHandler, err = NewStaticHandler(config)
		if err != nil {
			return nil, err
		}
	}
	result := &Site{
		name:              name,
		config:            config,
		staticHandler:     staticHandler,
		httpsRedirectBase: httpsRedirectHost,
		proxyPassURL:      proxyPassURL,
	}

	result.CreateGrpcChannels()

	return result, nil
}

func (host *Site) FindEndpoint(req *http.Request) (result *GrpcEndpoint) {
	path := req.RequestURI
	if strings.HasPrefix(path, "/") {
		path = path[1:]
	}
	pathParts := strings.Split(path, "/")
	if len(pathParts) < 1 {
		return nil
	}
	key := pathParts[0]
	if value, ok := host.endpoints[key]; ok {
		return value
	}
	return nil
}

func (host *Site) Serve(wr http.ResponseWriter, req *http.Request) {
	isGrpcWeb := strings.HasPrefix(req.Header.Get("Content-Type"), "application/grpc-web")
	isGrpc := !isGrpcWeb && strings.HasPrefix(req.Header.Get("Content-Type"), "application/grpc")
	endpoint := host.FindEndpoint(req)
	if req.TLS == nil && host.httpsRedirectBase != "" && !isGrpc && !isGrpcWeb {
		log.Debugf("%s requested %s via http, redirecting to https", req.RemoteAddr, req.URL.Path)
		// force using https instead of http in case if http supported by host instance
		redirectUrl := req.URL
		redirectUrl.Scheme = "https"
		redirectUrl.Host = host.httpsRedirectBase
		redirectString := redirectUrl.Redacted()
		http.Redirect(wr, req, redirectString, 302)
		return
	}
	if req.Method == "POST" && isGrpcWeb && endpoint != nil {
		// use gRPC-Listen to gGRP package to proxy
		if endpoint.grpcWebServer == nil {
			errorMessage := fmt.Sprintf("no connection to %s", endpoint.target)
			http.Error(wr, errorMessage, 503)
			return
		}
		log.Printf("%s requested %v using gRPC-Web protocol, proxied to %s",
			req.RemoteAddr,
			req.URL,
			endpoint.target,
		)
		endpoint.grpcWebServer.ServeHTTP(wr, req)
		return
	}
	if req.Method == "POST" && isGrpc && endpoint != nil {
		// just proxy to gRPC server
		if endpoint.grpcServer == nil {
			errorMessage := fmt.Sprintf("no connection to %s", endpoint.target)
			http.Error(wr, errorMessage, 503)
			return
		}
		log.Printf("%s requested %v using gRPC protocol, proxied to %s",
			req.RemoteAddr,
			req.URL,
			endpoint.target,
		)
		endpoint.grpcServer.ServeHTTP(wr, req)
		return
	}
	if host.proxyPassURL != nil {
		// redirect to another server
		proxyRequestUrl := host.proxyPassURL
		proxyRequestUrl.Path += req.URL.Path
		proxyRequestUrl.RawQuery = req.URL.RawQuery
		proxyRequest := &http.Request{
			URL:      proxyRequestUrl,
			Method:   req.Method,
			PostForm: req.PostForm,
			Body:     req.Body,
			Header:   req.Header,
		}
		log.Debugf("%s requested %v, will proxy to %v", req.RemoteAddr, req.URL, *host.proxyPassURL)
		client := http.DefaultClient
		proxyResponse, err := client.Do(proxyRequest)
		if err != nil {
			http.Error(wr, fmt.Sprintf("%v", err), 500)
			return
		}
		for key, values := range proxyResponse.Header {
			for _, value := range values {
				wr.Header().Add(key, value)
			}
		}
		wr.WriteHeader(proxyResponse.StatusCode)
		buffer := make([]byte, 4*1024*1024)
		size := proxyResponse.ContentLength
		var written int64 = 0
		for written < size {
			n, err := proxyResponse.Body.Read(buffer)
			if err != nil && err != io.EOF {
				http.Error(wr, fmt.Sprintf("%v", err), 503)
				return
			}
			chunk := buffer[0:n]
			_, err = wr.Write(chunk)
			if err != nil {
				break
			}
			written += int64(n)
		}
		return
	}
	if req.Method == "GET" && host.staticHandler != nil {
		// return Listen Application static files
		host.staticHandler.Handle(wr, req)
		return
	}
}

func CreateEndpointConnection(endpoint *EndpointConfig) (conn *grpc.ClientConn, target string, err error) {
	useSSL := false
	endpointURL := endpoint.ServiceURL
	scheme := endpointURL.Scheme
	if scheme == "http" || scheme == "https" || scheme == "grpc" || scheme == "grpcs" {
		port, err := strconv.Atoi(endpointURL.Port())
		if err != nil {
			return nil, "", fmt.Errorf("wrong port number %v in endpoint url %v", err, endpointURL)
		}
		if port == 0 {
			if endpointURL.Scheme == "http" {
				port = 80
			} else if endpointURL.Scheme == "https" {
				port = 443
			} else {
				return nil, "", fmt.Errorf("not port number specified for grpc scheme in endpoint url %v", endpointURL)
			}
		}
		useSSL = endpointURL.Scheme == "https" || endpointURL.Scheme == "grpcs"
		target = endpointURL.Hostname() + ":" + strconv.Itoa(port)
	} else if scheme == "unix" || scheme == "grpc+unix" {
		target = "unix:///" + endpointURL.Path
	} else {
		return nil, "", fmt.Errorf("unknown endpoint url scheme %v", endpointURL)
	}

	if useSSL {
		conn, err = grpc.Dial(target, grpc.WithCodec(proxy.Codec()))
	} else {
		conn, err = grpc.Dial(target, grpc.WithInsecure(), grpc.WithCodec(proxy.Codec()))
	}
	return conn, target, err
}

func (host *Site) CreateGrpcChannels() {
	host.endpoints = make(map[string]*GrpcEndpoint)
	for _, entry := range host.config.Endpoints {
		serviceName := entry.ServiceName
		var endpointEntry *GrpcEndpoint
		var hasEndpoint bool
		if endpointEntry, hasEndpoint = host.endpoints[serviceName]; !hasEndpoint {
			endpointEntry = &GrpcEndpoint{}
			host.endpoints[serviceName] = endpointEntry
		}
		grpcRedirector := func(ctx context.Context, method string) (context.Context, *grpc.ClientConn, error) {
			md, _ := metadata.FromIncomingContext(ctx)
			proxyMd := md.Copy()
			proxyMd.Delete("User-Agent")
			proxyMd.Delete("Connection")
			proxyCtx, _ := context.WithCancel(ctx)
			proxyCtx = metadata.NewOutgoingContext(proxyCtx, proxyMd)
			var err error
			if endpointEntry.grpcClient == nil {
				endpointEntry.grpcClient, endpointEntry.target, err = CreateEndpointConnection(entry)
				if err == nil {
					log.Printf("connected to gRPC server %v", entry.ServiceURL)
				} else {
					log.Warningf("cant connect to gRPC server %v: %v", entry.ServiceURL, err)
				}
			}
			return proxyCtx, endpointEntry.grpcClient, err
		}
		endpointEntry.grpcServer = grpc.NewServer(
			grpc.CustomCodec(proxy.Codec()),
			grpc.UnknownServiceHandler(proxy.TransparentHandler(grpcRedirector)),
		)
		endpointEntry.grpcWebServer = grpcweb.WrapServer(endpointEntry.grpcServer)
	}
}

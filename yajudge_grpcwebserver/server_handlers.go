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

type Site struct {
	name              string
	config            *SiteConfig
	staticHandler     *StaticHandler
	httpsRedirectBase string
	proxyPassURL      *url.URL
	grpcServer        *grpc.Server
	grpcWebServer     *grpcweb.WrappedGrpcServer
	grpcClient        *grpc.ClientConn
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
			hostName = originUrl.Host
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
	if config.GrpcBackendHost != "" && config.GrpcBackendPort > 0 {
		result.CreateGrpcChannels()
	}
	return result, nil
}

func (host *Site) Serve(wr http.ResponseWriter, req *http.Request) {
	isGrpcWeb := strings.HasPrefix(req.Header.Get("Content-Type"), "application/grpc-web")
	isGrpc := !isGrpcWeb && strings.HasPrefix(req.Header.Get("Content-Type"), "application/grpc")
	if req.TLS == nil && host.httpsRedirectBase != "" && !isGrpc && !isGrpcWeb {
		log.Printf("%s requested %s via http, redirecting to https", req.RemoteAddr, req.URL.Path)
		// force using https instead of http in case if http supported by host instance
		redirectUrl := req.URL
		redirectUrl.Scheme = "https"
		redirectUrl.Host = host.httpsRedirectBase
		redirectString := redirectUrl.Redacted()
		http.Redirect(wr, req, redirectString, 302)
		return
	}
	if req.Method == "POST" && isGrpcWeb {
		// use gRPC-Listen to gGRP package to proxy
		if host.grpcWebServer == nil {
			errorMessage := fmt.Sprintf("no connection to %s:%d", host.config.GrpcBackendHost, host.config.GrpcBackendPort)
			http.Error(wr, errorMessage, 503)
			return
		}
		log.Printf("%s requested %v using gRPC-Listen protocol, proxied to %s:%d",
			req.RemoteAddr,
			req.URL,
			host.config.GrpcBackendHost,
			host.config.GrpcBackendPort,
		)
		host.grpcWebServer.ServeHTTP(wr, req)
		return
	}
	if req.Method == "POST" && isGrpc {
		// just proxy to gRPC server
		if host.grpcServer == nil {
			errorMessage := fmt.Sprintf("no connection to %s:%d", host.config.GrpcBackendHost, host.config.GrpcBackendPort)
			http.Error(wr, errorMessage, 503)
			return
		}
		log.Printf("%s requested %v using gRPC protocol, proxied to %s:%d",
			req.RemoteAddr,
			req.URL,
			host.config.GrpcBackendHost,
			host.config.GrpcBackendPort,
		)
		host.grpcServer.ServeHTTP(wr, req)
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
		log.Printf("%s requested %v, will proxy to %v", req.RemoteAddr, req.URL, *host.proxyPassURL)
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

func (host *Site) CreateGrpcChannels() {
	grpcRedirector := func(ctx context.Context, method string) (context.Context, *grpc.ClientConn, error) {
		md, _ := metadata.FromIncomingContext(ctx)
		proxyMd := md.Copy()
		proxyMd.Delete("User-Agent")
		proxyMd.Delete("Connection")
		proxyCtx, _ := context.WithCancel(ctx)
		proxyCtx = metadata.NewOutgoingContext(proxyCtx, proxyMd)
		var err error
		if host.grpcClient == nil {
			grpcTarget := host.config.GrpcBackendHost + ":" + strconv.Itoa(host.config.GrpcBackendPort)
			host.grpcClient, err = grpc.Dial(
				grpcTarget,
				grpc.WithInsecure(),
				grpc.WithCodec(proxy.Codec()),
			)
			if err != nil {
				log.Printf("connected to gRPC server %s", grpcTarget)
			} else {
				log.Warningf("cant connect to gRPC server %s: %v", grpcTarget, err)
			}
		}
		return proxyCtx, host.grpcClient, err
	}
	host.grpcServer = grpc.NewServer(
		grpc.CustomCodec(proxy.Codec()),
		grpc.UnknownServiceHandler(proxy.TransparentHandler(grpcRedirector)),
	)
	host.grpcWebServer = grpcweb.WrapServer(host.grpcServer)
}

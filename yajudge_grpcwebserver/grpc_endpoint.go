package main

import (
	"context"
	"fmt"
	"github.com/improbable-eng/grpc-web/go/grpcweb"
	"github.com/mwitkow/grpc-proxy/proxy"
	log "github.com/sirupsen/logrus"
	"google.golang.org/grpc"
	"google.golang.org/grpc/metadata"
	"strconv"
	"sync"
)

type GrpcEndpoint struct {
	grpcServer    *grpc.Server
	grpcWebServer *grpcweb.WrappedGrpcServer
	grpcClient    *grpc.ClientConn
	config        *EndpointConfig
	target        string

	grpcMutex sync.RWMutex
}

func (endpoint *GrpcEndpoint) CreateEndpointConnection() (err error) {
	useSSL := false
	endpointURL := endpoint.config.ServiceURL
	scheme := endpointURL.Scheme
	if scheme == "http" || scheme == "https" || scheme == "grpc" || scheme == "grpcs" {
		port, err := strconv.Atoi(endpointURL.Port())
		if err != nil {
			return fmt.Errorf("wrong port number %v in endpoint url %v", err, endpointURL)
		}
		if port == 0 {
			if endpointURL.Scheme == "http" {
				port = 80
			} else if endpointURL.Scheme == "https" {
				port = 443
			} else {
				return fmt.Errorf("not port number specified for grpc scheme in endpoint url %v", endpointURL)
			}
		}
		useSSL = endpointURL.Scheme == "https" || endpointURL.Scheme == "grpcs"
		endpoint.target = endpointURL.Hostname() + ":" + strconv.Itoa(port)
	} else if scheme == "unix" || scheme == "grpc+unix" {
		endpoint.target = "unix:///" + endpointURL.Path
	} else {
		return fmt.Errorf("unknown endpoint url scheme %v", endpointURL)
	}
	endpoint.grpcMutex.Lock()
	if useSSL {
		endpoint.grpcClient, err = grpc.Dial(endpoint.target, grpc.WithCodec(proxy.Codec()))
	} else {
		endpoint.grpcClient, err = grpc.Dial(endpoint.target, grpc.WithInsecure(), grpc.WithCodec(proxy.Codec()))
	}
	endpoint.grpcMutex.Unlock()
	return err
}

func (endpoint *GrpcEndpoint) InvalidateEndpointConnection() {
	go func() {
		log.Infof("invalidating endpoint connection to %s", endpoint.config.ServiceName)
		endpoint.grpcMutex.Lock()
		endpoint.grpcClient = nil
		endpoint.grpcMutex.Unlock()
	}()
}

func (endpoint *GrpcEndpoint) GrpcRedirectHandler(ctx context.Context, method string) (context.Context, *grpc.ClientConn, error) {
	md, _ := metadata.FromIncomingContext(ctx)
	proxyMd := md.Copy()
	proxyMd.Delete("User-Agent")
	proxyMd.Delete("Connection")
	proxyCtx := metadata.NewOutgoingContext(ctx, proxyMd)
	var err error
	endpoint.grpcMutex.RLock()
	grpcClient := endpoint.grpcClient
	endpoint.grpcMutex.RUnlock()
	if grpcClient == nil {
		err = endpoint.CreateEndpointConnection()
		endpoint.grpcMutex.RLock()
		grpcClient = endpoint.grpcClient
		endpoint.grpcMutex.RUnlock()
		if err == nil {
			log.Printf("connected to gRPC server %v", endpoint.config.ServiceURL)
		} else {
			log.Warningf("cant connect to gRPC server %v: %v", endpoint.config.ServiceURL, err)
		}
	}
	return proxyCtx, grpcClient, err
}

func NewGrpcEndpoint(config *EndpointConfig) *GrpcEndpoint {
	grpcEndpoint := &GrpcEndpoint{
		config: config,
		target: config.ServiceName,
	}
	grpcEndpoint.grpcServer = grpc.NewServer(
		grpc.CustomCodec(proxy.Codec()),
		grpc.UnknownServiceHandler(proxy.TransparentHandler(grpcEndpoint.GrpcRedirectHandler)),
	)
	grpcEndpoint.grpcWebServer = grpcweb.WrapServer(grpcEndpoint.grpcServer)
	return grpcEndpoint
}

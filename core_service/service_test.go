package core_service

import (
	"context"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
	"testing"
)

const (
	listenAddress = "127.0.0.1:9095"
	authorizationToken = "abrakadabra"
)

var (
	testDatabaseProps = DatabaseProperties{
		Engine:   "postgres",
		Host:     "localhost",
		Port:     5432,
		User:     "test",
		Password: "qwerty",
		DBName:   "yajudge_test",
		SSLMode:  "disable",
	}
)

func createTestClientConnection(t *testing.T) *grpc.ClientConn {
	conn, err := grpc.Dial(listenAddress, grpc.WithInsecure())
	if err != nil {
		t.Fatalf("Can't connect to core_service: %s", err.Error())
	}
	return conn
}

func createTestContext() context.Context {
	ctx := context.Background()
	md := metadata.Pairs("auth", authorizationToken)
	return metadata.NewOutgoingContext(ctx, md)
}


func TestAuth(t *testing.T) {
	servicesContext, finish := context.WithCancel(context.Background())
	_, err := StartServices(servicesContext, listenAddress, authorizationToken, testDatabaseProps)
	if err != nil {
		t.Fatalf("Can't start services: %s", err.Error())
	}
	defer finish()
	conn := createTestClientConnection(t)
	client := NewUserManagementClient(conn)

	// try empty access
	_, err = client.Authorize(context.Background(), &User{})
	if err == nil {
		t.Fatalf("Unauthorized acces allowed")
	}

	// try wrong access
	wrongMd := metadata.Pairs("auth", "kek")
	_, err = client.Authorize(metadata.NewOutgoingContext(context.Background(), wrongMd), &User{})
	if err == nil {
		t.Fatalf("Bad authorization access allowed")
	}

	// should be access to core_service
	_, err = client.Authorize(createTestContext(), &User{})
	if err != nil {
		grpcCode, isGrpcErr := status.FromError(err)
		if !isGrpcErr {
			t.Fatalf("Expected gRPC InvalidArgument error, got '%v'", err)
		} else if grpcCode.Code() != codes.InvalidArgument {
			t.Fatalf("Expected gRPC InvalidArgument error, got '%v'", err)
		}
	}
}

func TestUserAuthentication(t *testing.T) {

}

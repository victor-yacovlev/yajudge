package core_service

import (
	"context"
	"database/sql"
	_ "embed"
	"fmt"
	_ "github.com/lib/pq"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
	"net"
	"strings"
	"time"
)

type DatabaseProperties struct {
	Engine		string		`json:"engine"`  	// default is postgres
	Host		string		`json:"host"`		// default is localhost
	Port		uint16		`json:"port"`		// default is 5432
	User		string		`json:"user"`
	Password	string		`json:"password"`
	DBName		string		`json:"db_name"`
	SSLMode		string		`json:"ssl_mode"`	// default is disable
}

type Services struct {
	DB						*sql.DB
	UserManagement			*UserManagementService
	CourseManagement		*CourseManagementService
}

//go:embed create_database_tables.sql
var createTablesQuerySql string


func (service *Services) CreateEmptyDatabase() {
	_, err := service.DB.Exec(createTablesQuerySql)
	if err != nil {
		panic(err)
	}
}


func NewPostgresDatabaseProperties() DatabaseProperties {
	return DatabaseProperties{
		Engine: "postgres", Host: "localhost", Port: 5432, SSLMode: "disable",
	}
}

func MakeDatabaseConnection(p DatabaseProperties) (*sql.DB, error) {
	switch p.Engine {
	case "postgres":
		dsn := fmt.Sprintf("host=%s port=%d user=%s password=%s dbname=%s sslmode=%s",
			p.Host, p.Port, p.User, p.Password, p.DBName, p.SSLMode)
		return sql.Open("postgres", dsn)
	default:
		return nil, fmt.Errorf("database engine '%s' not supported yet", p.Engine)
	}
}

func (services *Services) createAuthMiddlewares(genericAuthToken, gradersAuthToken string) []grpc.ServerOption {
	checkAuth := func(ctx context.Context, genericAuthToken string, graderOutToken, method string) bool {
		md, _ := metadata.FromIncomingContext(ctx)
		values := md.Get("auth")
		if len(values) == 0 {
			return false
		}
		auth := values[0]
		if strings.Contains(method, "ReceiveSubmissionsToGrade") || strings.Contains(method, "UpdateGraderOutput") {
			return auth == gradersAuthToken
		}
		if auth != genericAuthToken {
			return false
		}
		return true
	}
	result := make([]grpc.ServerOption, 2)
	result[0] = grpc.UnaryInterceptor(func(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (resp interface{}, err error) {
		if !checkAuth(ctx, genericAuthToken, gradersAuthToken, info.FullMethod) {
			return nil, status.Errorf(codes.Unauthenticated, "not authorized")
		}
		if !services.UserManagement.CheckUserSession(ctx, info.FullMethod) {
			return nil, status.Errorf(codes.PermissionDenied, "permission denied")
		}
		res, err := handler(ctx, req)
		_, isGrpcErr := status.FromError(err)
		if isGrpcErr {
			return res, err
		} else if err != nil {
			return res, status.Errorf(codes.Internal, "%s", err.Error())
		} else {
			return res, nil
		}
	})
	result[1] = grpc.StreamInterceptor(func(srv interface{}, ss grpc.ServerStream, info *grpc.StreamServerInfo, handler grpc.StreamHandler) error {
		if !checkAuth(ss.Context(), genericAuthToken, gradersAuthToken, info.FullMethod) {
			return status.Errorf(codes.Unauthenticated, "not authorized")
		}
		if !services.UserManagement.CheckUserSession(ss.Context(), info.FullMethod) {
			return status.Errorf(codes.PermissionDenied, "permission denied")
		}
		err := handler(srv, ss)
		_, isGrpcErr := status.FromError(err)
		if isGrpcErr {
			return err
		} else if err != nil {
			return status.Errorf(codes.Internal, "%s", err.Error())
		} else {
			return nil
		}
	})
	return result
}

func StartServices(ctx context.Context, listenAddress, genericAuthToken, gradersAuthToken string, dbProps DatabaseProperties) (res *Services, err error) {

	db, err := MakeDatabaseConnection(dbProps)
	if err != nil {
		return nil, err
	}

	res = &Services{DB: db}

	res.UserManagement = NewUserManagementService(res)
	res.CourseManagement = NewCourseManagementService(res)



	server := grpc.NewServer(res.createAuthMiddlewares(genericAuthToken, gradersAuthToken)...)

	RegisterUserManagementServer(server, res.UserManagement)
	RegisterCourseManagementServer(server, res.CourseManagement)

	lis, err := net.Listen("tcp", listenAddress)
	if err != nil {
		return nil, err
	}
	go func() {
		_ = server.Serve(lis)
	}()
	go func() {
		select {
		case <- ctx.Done():
			server.GracefulStop()
			lis.Close()
			time.Sleep(100 * time.Millisecond)
		}
	}()

	return res,nil
}

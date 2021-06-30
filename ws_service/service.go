package ws_service

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/gorilla/websocket"
	"google.golang.org/grpc"
	"google.golang.org/grpc/metadata"
	"net/http"
	"reflect"
	"strings"
)

type IncomingMessage struct {
	Id					int			`json:"id"`
	SessionCookie		string		`json:"session_cookie"`
	RequestService		string		`json:"request_service"`
	RequestMethod		string		`json:"request_method"`
	Argument			interface{}	`json:"argument"`
}

type OutgoingMessage struct {
	Id					int			`json:"id"`
	Error				string		`json:"error"`
	Result				interface{}	`json:"result"`
}

type Class struct {
	Pointer		interface{}
}

type WsService struct {
	ctx					context.Context
	authToken			string
	RegisteredClasses	map[string]Class
}

func NewWsService(authToken string, grpcServices []interface{}) (res *WsService) {
	res = new(WsService)
	res.RegisteredClasses = make(map[string]Class)
	for _, grpcClient := range grpcServices {
		res.RegisterService(grpcClient)
	}
	md := metadata.Pairs("auth", authToken)
	res.ctx = metadata.NewOutgoingContext(context.Background(), md)
	return res
}

func (service *WsService) RegisterService(srv interface{}) {
	serviceName := reflect.TypeOf(srv).Name()
	if strings.HasSuffix(serviceName, "Client") {
		serviceName = serviceName[0:len(serviceName)-6]
	}
	service.RegisteredClasses[serviceName] = Class{Pointer: srv}
}


var upgrader = websocket.Upgrader{}

func (service *WsService) HandleWsConnection(ws *websocket.Conn) {
	defer ws.Close()
	working := true
	for working {
		messageType, messageData, err := ws.ReadMessage()
		if err != nil {
			working = false
		}
		switch messageType {
		case websocket.PingMessage:
			ws.WriteMessage(websocket.PongMessage, make([]byte, 0))
		case websocket.TextMessage:
			response, err := service.ProcessTextMessage(messageData)
			if err != nil {
				// fatal error - can't work animore
				working = false
			}
			ws.WriteMessage(websocket.TextMessage, response)
		case websocket.BinaryMessage:
			// TODO implement BSON message format
		}
	}
}

func (service *WsService) ProcessTextMessage(in []byte) (out []byte, err error) {
	var inData IncomingMessage
	err = json.Unmarshal(in, &inData)
	if err != nil {
		return nil, err
	}
	res, err := service.ProcessMessage(inData.SessionCookie,
		inData.RequestService, inData.RequestMethod, inData.Argument)
	outData := OutgoingMessage{Id: inData.Id}
	if err != nil {
		outData.Error = err.Error()
	} else {
		outData.Result = res
	}
	out, err = json.Marshal(outData)
	return out, err
}

func (service *WsService) ProcessMessage(cookie string, className string,
	methodName string, argument interface{}) (res interface{}, err error) {
	class, classFound := service.RegisteredClasses[className]
	if !classFound {
		return nil, fmt.Errorf("class not found: %s", className)
	}
	method, methodFound := reflect.TypeOf(class.Pointer).MethodByName(methodName)
	if !methodFound {
		return nil, fmt.Errorf("method %s not found in class %s",
			methodName, className)
	}
	ctx := context.Background()
	args := make([]reflect.Value, 3)
	args[0] = reflect.ValueOf(class.Pointer)
	args[1] = reflect.ValueOf(ctx)
	args[2] = reflect.ValueOf(argument)
	retvals := method.Func.Call(args)
	resRetval := retvals[0].Interface()
	errRetval := retvals[1].Interface()
	return resRetval, errRetval.(error)
}

func (service *WsService) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	ws, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		w.WriteHeader(500)
		w.Write([]byte(err.Error()))
	}
	defer ws.Close()
	service.HandleWsConnection(ws)
}

func StartWebsocketHttpHandler(authToken string, grpcAddr string) (http.Handler, error) {
	var err error
	users, err := grpc.Dial(grpcAddr, grpc.WithInsecure())
	if err != nil {
		return nil, err
	}
	courses, err := grpc.Dial(grpcAddr, grpc.WithInsecure())
	if err != nil {
		return nil, err
	}
	service := NewWsService(authToken, []interface{}{
		users, courses,
	})
	return service, nil
}

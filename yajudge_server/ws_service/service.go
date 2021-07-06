package ws_service

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/gorilla/websocket"
	"google.golang.org/grpc"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
	"net/http"
	"reflect"
	"strings"
	core_service "yajudge/service"
)

type IncomingMessage struct {
	Id       int         `json:"id"`
	Session  string      `json:"session"`
	Service  string      `json:"service"`
	Method   string      `json:"method"`
	Type     string      `json:"type"`
	Argument interface{} `json:"argument"`
}

type ErrorMessage struct {
	Code	int64		`json:"code"`
	Desc	string		`json:"desc"`
}

type OutgoingMessage struct {
	Id     int			`json:"id"`
	Error  ErrorMessage `json:"error"`
	Type   string       `json:"type"`
	Result interface{}  `json:"result"`
}

type ClassMethod struct {
	Name		string
	Func		reflect.Value
	ArgType		reflect.Type
}

type Class struct {
	Instance	interface{}
	Methods		map[string]ClassMethod
}

type WsService struct {
	AuthToken         string
	RegisteredClasses map[string]Class
}

func NewWsService(authToken string) (res *WsService) {
	res = new(WsService)
	res.RegisteredClasses = make(map[string]Class)
	res.AuthToken = authToken
	return res
}

func (service *WsService) RegisterService(name string, srv interface{}) {
	typee := reflect.TypeOf(srv)
	class := Class{
		Instance: srv,
		Methods: make(map[string]ClassMethod),
	}
	methodsCount := typee.NumMethod()
	for i:=0; i<methodsCount; i++ {
		method := typee.Method(i)
		methodName := method.Name
		funcType := method.Type
		argType := funcType.In(2).Elem()
		argTypeName := argType.Name()
		_ = argTypeName
		m := ClassMethod{
			Name: methodName,
			Func: method.Func,
			ArgType: argType,
		}
		class.Methods[methodName] = m
	}
	service.RegisteredClasses[name] = class
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
	if inData.Type == "" {
		return nil, fmt.Errorf("method type not specified, must be 'unary' or 'stream'")
	} else if inData.Type == "unary" {
		res, err := service.ProcessUnaryMessage(inData.Session,
			inData.Service, inData.Method, inData.Argument)
		outData := OutgoingMessage{Id: inData.Id, Type: "unary"}
		if err != nil {
			outData.Error.Code = 99999;
			outData.Error.Desc = err.Error()
			grpcErr := status.Convert(err)
			if grpcErr != nil {
				outData.Error.Code = int64(grpcErr.Code())
				outData.Error.Desc = grpcErr.Message()
			}
		} else {
			outData.Result = res
		}
		out, err = json.Marshal(outData)
	}
	return out, err
}

func ArgumentMapToValue(argType reflect.Type, data map[string]interface{}) (res reflect.Value, err error) {
	fieldsCount := argType.NumField()
	res = reflect.New(argType)
	for i:=0; i<fieldsCount; i++ {
		field := argType.Field(i)
		jsonTag := field.Tag.Get("json")
		if jsonTag=="" {
			continue
		}
		tagParams := strings.Split(jsonTag, ",")
		jsonFieldName := tagParams[0]
		jsonValue, hasHavlue := data[jsonFieldName]
		var fieldVal reflect.Value
		if !hasHavlue {
			continue
		}
		fieldType := field.Type
		if fieldType.Kind() == reflect.Int64 {
			intVal, isInt := jsonValue.(int64)
			floatVal, isFloat := jsonValue.(float64)
			if isInt {
				fieldVal = reflect.ValueOf(intVal)
			} else if isFloat {
				fieldVal = reflect.ValueOf(int64(floatVal))
			} else {
				return res, fmt.Errorf("can't convert '%v' to int64 for field '%s'", jsonValue, jsonFieldName)
			}
		} else if fieldType.Kind() == reflect.Float64 {
			floatVal, isFloat := jsonValue.(float64)
			if isFloat {
				fieldVal = reflect.ValueOf(floatVal)
			} else {
				return res, fmt.Errorf("can't convert '%v' to float64 for field '%s'", jsonValue, jsonFieldName)
			}
		} else if fieldType.Kind() == reflect.String {
			strVal, isStr := jsonValue.(string)
			if isStr {
				fieldVal = reflect.ValueOf(strVal)
			} else {
				return res, fmt.Errorf("can't convert '%v' to string for field '%s'", jsonValue, jsonFieldName)
			}
		} else if fieldType.Kind() == reflect.Bool {
			boolVal, isBool := jsonValue.(bool)
			if isBool {
				fieldVal = reflect.ValueOf(boolVal)
			} else {
				return res, fmt.Errorf("can't convert '%v' to bool for field '%s'", jsonValue, jsonFieldName)
			}
		}
		res.Elem().Field(i).Set(fieldVal)
	}
	return
}

func (service *WsService) ProcessUnaryMessage(cookie string, className string,
	methodName string, argument interface{}) (res interface{}, err error) {
	class, classFound := service.RegisteredClasses[className]
	if !classFound {
		return nil, fmt.Errorf("class not found: %s", className)
	}
	method, methodFound := class.Methods[methodName]
	_ = method
	if !methodFound {
		return nil, fmt.Errorf("method %s not found in class %s",
			methodName, className)
	}
	if argument == nil {
		return nil, fmt.Errorf("method argument is required")
	}
	argumentMap, argumentIsMap := argument.(map[string]interface{})
	if !argumentIsMap {
		return nil, fmt.Errorf("method argument must be a struct of fields")
	}
	argumentValue, err := ArgumentMapToValue(method.ArgType, argumentMap)
	if err != nil {
		return nil, err
	}
	var md metadata.MD
	if cookie != "" {
		md = metadata.Pairs("auth", service.AuthToken, "session", cookie)
	} else {
		md = metadata.Pairs("auth", service.AuthToken)
	}
	ctx := metadata.NewOutgoingContext(context.Background(), md)
	args := []reflect.Value{
		reflect.ValueOf(class.Instance),
		reflect.ValueOf(ctx),
		argumentValue,
	}
	retvals := method.Func.Call(args)
	res = retvals[0].Interface()
	errOrNil := retvals[1].Interface()
	if errOrNil != nil {
		err = errOrNil.(error)
	}
	return res, err
}

func (service *WsService) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	upgrader.CheckOrigin = func(r *http.Request) bool {
		return true
	}
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
	grpcConn, err := grpc.Dial(grpcAddr, grpc.WithInsecure())
	if err != nil {
		return nil, err
	}
	users := core_service.NewUserManagementClient(grpcConn)
	courses := core_service.NewCourseManagementClient(grpcConn)
	_ = users
	service := NewWsService(authToken)
	service.RegisterService("UserManagement", users)
	service.RegisterService("CourseManagement", courses)
	return service, nil
}

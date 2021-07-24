package ws_service

import (
	"bytes"
	"compress/gzip"
	"context"
	"encoding/json"
	"fmt"
	"github.com/gorilla/websocket"
	"google.golang.org/grpc"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
	"io"
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

func decompress(src []byte) (out []byte, err error) {
	reader, err := gzip.NewReader(bytes.NewReader(src))
	if err != nil {
		return nil, err
	}
	const bufSize = 10
	buffer := make([]byte, bufSize)
	result := make([]byte, 0)
	n := 0
	for {
		n, err = reader.Read(buffer)
		if err != nil && err != io.EOF {
			return nil, err
		}
		if n > 0 {
			result = append(result, buffer[0:n]...)
		}
		if err == io.EOF {
			break
		}
	}
	return result, nil
}

func compress(src []byte) (out []byte, err error) {
	var buf bytes.Buffer
	writer, err := gzip.NewWriterLevel(&buf, gzip.BestCompression)
	_, err = writer.Write(src)
	if err != nil {
		return nil, err
	}
	writer.Close()
	return buf.Bytes(), nil
}

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
			uncompressedRequest, _ := decompress(messageData)
			response, _ := service.ProcessTextMessage(uncompressedRequest)
			compressedResponse, _ := compress(response)
			ws.WriteMessage(websocket.BinaryMessage, compressedResponse)
		}
	}
}

func (service *WsService) ProcessTextMessage(in []byte) (out []byte, err error) {
	var inData IncomingMessage
	err = json.Unmarshal(in, &inData)
	outStr := ""
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
		outStr, err = ToNonEmptyjson(outData)
	}
	return []byte(outStr), err
}

// ToNonEmptyjson is a custom JSON marshaler to provide most compatible JSON output:
// - ignores 'omitempty' option generated by protoc
// - creates empty arrays instead of null value
func ToNonEmptyjson(s interface{}) (res string, err error) {
	sType := reflect.TypeOf(s)
	if sType.Kind() != reflect.Ptr && sType.Kind() != reflect.Struct {
		defaultJson, err := json.Marshal(s)
		return string(defaultJson), err
	}
	sVal := reflect.ValueOf(s)
	if sType.Kind() == reflect.Ptr {
		sType = sType.Elem()
		sVal = sVal.Elem()
	}
	if sType.Kind() != reflect.Struct {
		defaultJson, err := json.Marshal(s)
		return string(defaultJson), err
	}
	fieldsCount := sType.NumField()
	res = res + "{ "
	for i:=0; i<fieldsCount; i++ {
		field := sVal.Field(i)
		jsonTag := sType.Field(i).Tag.Get("json")
		if jsonTag == "" {
			continue
		}
		jsonOpts := strings.Split(jsonTag, ",")
		jsonKey := jsonOpts[0]
		if len(res) > 2 {
			res += ", "
		}
		res += "\"" + jsonKey + "\": "
		fieldKind := field.Type().Kind()
		if fieldKind == reflect.Ptr {
			if field.IsNil() {
				field = reflect.New(field.Type())
			}
			field = field.Elem()
			fieldKind = field.Type().Kind()
		}
		if fieldKind == reflect.Struct || fieldKind == reflect.Interface {
			var valueToSave interface{}
			if field.IsValid() && field.Interface()!=nil {
				valueToSave = field.Interface()
			} else {
				valueToSave = reflect.New(field.Type()).Interface()
			}
			var fieldData string
			if valueToSave == nil {
				fieldData = "null";
			} else {
				fieldData, err = ToNonEmptyjson(valueToSave)
			}
			if err != nil {
				return "", err
			}
			res += fieldData
		} else if field.Type().Kind() == reflect.Slice {
			res += "["
			if !field.IsNil() {
				itemsCount := field.Len()
				for j:=0; j<itemsCount; j++ {
					if j > 0 {
						res += ", "
					}
					sliceItem := field.Index(j)
					itemData, err := ToNonEmptyjson(sliceItem.Interface())
					if err != nil {
						return "", err
					}
					res += itemData
				}
			}
			res += "]"
		} else {
			defaultJson, err := json.Marshal(field.Interface())
			if err != nil {
				return "", err
			}
			res += string(defaultJson)
		}
	}
	res = res + " }"
	return res, nil
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
		fieldKind := fieldType.Kind()
		if fieldKind == reflect.Int64 || fieldKind == reflect.Int32 {
			int64Val, isInt64 := jsonValue.(int64)
			floatVal, isFloat := jsonValue.(float64)
			var intVal int64
			if isInt64 {
				intVal = int64Val
			} else if isFloat {
				intVal = int64(floatVal)
			} else {
				return res, fmt.Errorf("can't convert '%v' to int for field '%s'", jsonValue, jsonFieldName)
			}
			if fieldKind == reflect.Int64 {
				fieldVal = reflect.ValueOf(intVal)
			} else {
				int32Val := int32(intVal)
				fieldVal = reflect.ValueOf(int32Val)
			}
		} else if fieldKind == reflect.Float64 {
			floatVal, isFloat := jsonValue.(float64)
			if isFloat {
				fieldVal = reflect.ValueOf(floatVal)
			} else {
				return res, fmt.Errorf("can't convert '%v' to float64 for field '%s'", jsonValue, jsonFieldName)
			}
		} else if fieldKind == reflect.String {
			strVal, isStr := jsonValue.(string)
			if isStr {
				fieldVal = reflect.ValueOf(strVal)
			} else {
				return res, fmt.Errorf("can't convert '%v' to string for field '%s'", jsonValue, jsonFieldName)
			}
		} else if fieldKind == reflect.Bool {
			boolVal, isBool := jsonValue.(bool)
			if isBool {
				fieldVal = reflect.ValueOf(boolVal)
			} else {
				return res, fmt.Errorf("can't convert '%v' to bool for field '%s'", jsonValue, jsonFieldName)
			}
		} else if fieldKind == reflect.Ptr {
			fieldTargetType := fieldType.Elem()
			mapVal, isMap := jsonValue.(map[string]interface{})
			if isMap {
				fieldVal, err = ArgumentMapToValue(fieldTargetType, mapVal)
				if err != nil {
					return res, err
				}
			} else {
				return res, fmt.Errorf("can't convert '%v' to '%s' for field '%s'",
					jsonValue, fieldTargetType.Name(), jsonFieldName)
			}
		} else if fieldKind == reflect.Slice {
			sliceVal, isSlice := jsonValue.([]interface{})
			fieldTargetType := fieldType.Elem()
			if fieldTargetType.Kind() == reflect.Ptr {
				fieldTargetType = fieldTargetType.Elem()
			}
			if isSlice {
				itemsCount := len(sliceVal)
				fieldVal = reflect.MakeSlice(fieldType, itemsCount, itemsCount)
				for index:=0; index<itemsCount; index++ {
					jsonItem := sliceVal[index]
					jsonItemAsMessage := jsonItem.(map[string]interface{})
					itemVal, err := ArgumentMapToValue(fieldTargetType, jsonItemAsMessage)
					if err != nil {
						return res, err
					}
					fieldVal.Index(index).Set(itemVal)
				}
			} else {
				return res, fmt.Errorf("can't convert '%v' to '[]%s' for field '%s'",
					jsonValue, fieldTargetType.Name(), jsonFieldName)
			}
		}
		structField := res.Elem().Field(i)
		structFieldType := structField.Type()
		fieldValType := fieldVal.Type()
		if structFieldType.Name() != fieldValType.Name() && fieldValType.Name()=="int32" {
			// some dirty hack for enum values
			enumValue := reflect.New(structFieldType).Elem()
			enumValue.SetInt(fieldVal.Int())
			structField.Set(enumValue)
		} else {
			structField.Set(fieldVal)
		}
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

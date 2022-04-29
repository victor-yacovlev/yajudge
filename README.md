# Yet Another Judge 

Learning management and programming tasks submissions grader.

Almost everything implemented using 
[Dart Programming Language](https://dart.dev) and
use [gRPC Framework](https://grpc.io) for inter-component
communication.

Requires Dart >= 2.12 and Protobuf Compiler to build 
server-side components and 
also [Flutter SDK](https://flutter.dev) >= 2.8 to 
build client-side app.

To build gRPC-Web proxy server also required [GoLang](https://go.dev) >= 1.16.

## Usage and Documentation

Documentation on content preparation explained in Russian using Demo course
matching this repository [demo](./demo) subdirectory.

Demo course in Russian available at [demo.yajudge.ru](https://demo.yajudge.ru). 

## Build

 1. Make sure you have `dart`, `go`, `flutter` and `protobuf-compiler`
packages installed
 2. Run `make` to build everything but native client apps
 3. To build native client app for current platform
(only macOS and partially Linux/GTK implemented yet)
run `make native-client` in `yajudge_client` subdirectory.
 
## Components of software

See README.md in subdirectories for details):

 - [yajudge_master](./yajudge_master) - server-side backend to manage
courses, problems and students
 - [yajudge_client](./yajudge_client) - frontend app for Web and Desktops
 - [yajudge_grader](./yajudge_grader) - submissions grader to be run on
the same hosts as master or run on independent hosts
 - [yajudge_common](./yajudge_common) - common library required by all
three components listed above
 - [yajudge_grpcwebserver](./yajudge_grpcwebserver) - web-server to handle
static files exposed by `yajudge_client` and to handle both gRPC-Web 
and gRPC-Native requests within the same host:port address.

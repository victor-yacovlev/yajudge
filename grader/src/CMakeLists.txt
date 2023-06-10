cmake_minimum_required(VERSION 3.16.3)
project(grader)

set(BIN_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../bin")
set(CONF_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../conf")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${BIN_DIR}")
set(CMAKE_CXX_STANDARD 17)

find_package(Poco REQUIRED Foundation Util)
find_package(yaml-cpp REQUIRED)
find_package(Protobuf REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(GRPC REQUIRED grpc++)

include_directories(${Protobuf_INCLUDE_DIRS})
include_directories(${YAML_CPP_INCLUDE_DIR})
include_directories(${GRPC_INCLUDE_DIR})
include_directories(${CMAKE_CURRENT_BINARY_DIR})

set(SOURCES
    main.cpp

    RPC.cpp
    Grader.cpp
    Properties.cpp
    Util.cpp
)

set(PROTO_DIR "../../yajudge_common/proto")
set(PROTOS
    "${PROTO_DIR}/yajudge_common.proto"
    "${PROTO_DIR}/yajudge_courses_content.proto"
    "${PROTO_DIR}/yajudge_submissions.proto"
)

set(PROTO_GENERATED
    "${CMAKE_CURRENT_BINARY_DIR}/yajudge_common.pb.h"
    "${CMAKE_CURRENT_BINARY_DIR}/yajudge_courses_content.pb.h"
    "${CMAKE_CURRENT_BINARY_DIR}/yajudge_submissions.pb.h"
    "${CMAKE_CURRENT_BINARY_DIR}/yajudge_common.grpc.pb.h"
    "${CMAKE_CURRENT_BINARY_DIR}/yajudge_courses_content.grpc.pb.h"
    "${CMAKE_CURRENT_BINARY_DIR}/yajudge_submissions.grpc.pb.h"

    "${CMAKE_CURRENT_BINARY_DIR}/yajudge_common.pb.cc"
    "${CMAKE_CURRENT_BINARY_DIR}/yajudge_courses_content.pb.cc"
    "${CMAKE_CURRENT_BINARY_DIR}/yajudge_submissions.pb.cc"
    "${CMAKE_CURRENT_BINARY_DIR}/yajudge_common.grpc.pb.cc"
    "${CMAKE_CURRENT_BINARY_DIR}/yajudge_courses_content.grpc.pb.cc"
    "${CMAKE_CURRENT_BINARY_DIR}/yajudge_submissions.grpc.pb.cc"
)

find_program(GRPC_CPP_PLUGIN grpc_cpp_plugin)
add_custom_command(
    OUTPUT ${PROTO_GENERATED}
    COMMAND ${Protobuf_PROTOC_EXECUTABLE}
    ARGS
    --grpc_out "${CMAKE_CURRENT_BINARY_DIR}"
    --cpp_out "${CMAKE_CURRENT_BINARY_DIR}"
    -I "${PROTO_DIR}"
    --plugin=protoc-gen-grpc="${GRPC_CPP_PLUGIN}"
    ${PROTOS}
    DEPENDS ${PROTOS}
)

add_executable(grader ${SOURCES} ${PROTO_GENERATED})
target_link_libraries(
    grader

    Poco::Foundation
    Poco::Util
    ${YAML_CPP_LIBRARIES}
    ${Protobuf_LIBRARIES}
    ${GRPC_LIBRARIES}
)

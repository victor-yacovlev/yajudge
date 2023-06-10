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

set(PROTOS
    ../../yajudge_common/proto/yajudge_common.proto
    ../../yajudge_common/proto/yajudge_courses_content.proto
    ../../yajudge_common/proto/yajudge_submissions.proto
)

protobuf_generate_cpp(PROTO_SRCS PROTO_HDRS ${PROTOS})

add_executable(grader ${SOURCES} ${PROTO_SRCS} ${PROTO_HDRS})
target_link_libraries(
    grader

    Poco::Foundation
    Poco::Util
    ${YAML_CPP_LIBRARIES}
    ${Protobuf_LIBRARIES}
    ${GRPC_LIBRARIES}
)


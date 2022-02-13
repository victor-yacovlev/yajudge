cmake_minimum_required(VERSION 3.10)
project(yajudge-helpers)
find_package(PkgConfig REQUIRED)

set(CMAKE_C_STANDARD 11)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY  "${CMAKE_CURRENT_SOURCE_DIR}/../libexec")

pkg_check_modules(CAP REQUIRED libcap)

add_executable(overlay-mount overlay-mount.c)
target_include_directories(overlay-mount PRIVATE ${CAP_INCLUDE_DIRS})
target_compile_options(overlay-mount PRIVATE ${CAP_CFLAGS_OTHER})
target_link_libraries(overlay-mount ${CAP_LIBRARIES})

add_executable(limited-run limited-run.c)
add_executable(initial-cgroup-setup initial-cgroup-setup.c)

# build a library to check for errors
# this file will be compiled into targets
add_library(syscall-wrappers syscall-wrappers.c)


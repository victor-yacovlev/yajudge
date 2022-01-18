cmake_minimum_required(VERSION 3.10)
project(yajudge-helpers)
find_package(PkgConfig REQUIRED)

if (${CMAKE_SYSTEM_NAME} MATCHES "Linux")
    pkg_check_modules(FUSE REQUIRED fuse3)
else()
    message(FATAL_ERROR "Unsupported operation system")
endif()


add_executable(yajudge-overlay-fs overlay-fs.cpp)
target_link_libraries(yajudge-overlay-fs ${FUSE_LIBRARIES})
target_include_directories(yajudge-overlay-fs PRIVATE ${FUSE_INCLUDE_DIRS})
target_compile_options(yajudge-overlay-fs PRIVATE ${FUSE_CFLAGS_OTHER})
add_executable(yajudge-launcher guarded-launcher.cpp)

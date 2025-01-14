#
# CMakeLists.txt
# zed-open-capture-mac
#
# Created by Christian Bator on 01/10/2025
#

cmake_minimum_required(VERSION 3.31)

#
# Project Info
#
set(PROJECT_NAME "ZEDOpenCaptureMac")
project(${PROJECT_NAME} LANGUAGES CXX OBJC)

#
# Compiler
#
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED TRUE)

#
# Source
#
set(INCLUDE_DIR "${CMAKE_SOURCE_DIR}/include")

file(GLOB_RECURSE HEADERS
    "${INCLUDE_DIR}/*.h"
    "${INCLUDE_DIR}/*.hpp"
)

set(SRC_DIR "${CMAKE_SOURCE_DIR}/src")

file(GLOB_RECURSE SOURCES
    "${SRC_DIR}/*.cpp"
    "${SRC_DIR}/*.m"
    "${SRC_DIR}/*.mm"
)

# add_executable(${PROJECT_NAME} ${SOURCES})

add_library(${PROJECT_NAME} SHARED
    ${SOURCES}
)

#
# Dependencies
#
target_link_libraries(${PROJECT_NAME}
    PUBLIC
    "-framework Foundation"
    "-framework AVFoundation"
    "-framework CoreMedia"
    "-framework CoreVideo"
    "-framework CoreGraphics"
    "-framework Accelerate"
)

#
# Install
#
set(CMAKE_INSTALL_PREFIX "/opt/stereolabs")

install(TARGETS ${PROJECT_NAME} DESTINATION lib)
install(FILES ${HEADERS} DESTINATION include)

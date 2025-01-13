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
set(PROJECT_NAME "zed-open-capture-mac")
project(${PROJECT_NAME} LANGUAGES CXX OBJC)

#
# Compiler
#
find_program(CLANG_PATH NAMES clang++ PATHS /opt/homebrew/opt/llvm/bin)
set(CMAKE_CXX_COMPILER ${CLANG_PATH})
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED TRUE)

#
# Build Type
#
set(CMAKE_BUILD_TYPE Debug)

#
# Source
#
set(SRC_DIR "${CMAKE_SOURCE_DIR}/src")

file(GLOB_RECURSE SOURCES
    "${SRC_DIR}/*.cpp"
    "${SRC_DIR}/*.m"
    "${SRC_DIR}/*.mm"
)

add_executable(${PROJECT_NAME} ${SOURCES})

#
# Dependencies
#
find_library(FOUNDATION_FRAMEWORK Foundation)
find_library(AVFOUNDATION_FRAMEWORK AVFoundation)
find_library(COREMEDIA_FRAMEWORK CoreMedia)
find_library(COREVIDEO_FRAMEWORK CoreVideo)
find_library(COREGRAPHICS_FRAMEWORK CoreGraphics)
find_library(ACCELERATE_FRAMEWORK Accelerate)
find_package(OpenCV REQUIRED)

target_include_directories(${PROJECT_NAME}
    PRIVATE
    ${OpenCV_INCLUDE_DIRS}
)

target_link_libraries(${PROJECT_NAME}
    PRIVATE
    ${FOUNDATION_FRAMEWORK}
    ${AVFOUNDATION_FRAMEWORK}
    ${COREMEDIA_FRAMEWORK}
    ${COREVIDEO_FRAMEWORK}
    ${COREGRAPHICS_FRAMEWORK}
    ${ACCELERATE_FRAMEWORK}
    ${OpenCV_LIBS}
)

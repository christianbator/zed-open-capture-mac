#
# CMakeLists.txt
# zed-open-capture-mac
#
# Created by Christian Bator on 01/13/2025
#

cmake_minimum_required(VERSION 3.31)

#
# Project Info
#
set(PROJECT_NAME "Examples")
project(${PROJECT_NAME} LANGUAGES CXX)

#
# Compiler
#
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED TRUE)

#
# Source
#
file(GLOB SOURCES
    ${CMAKE_SOURCE_DIR}/*.cpp
)

set(TARGET_NAMES)

foreach(SRC ${SOURCES})
    get_filename_component(TARGET_NAME ${SRC} NAME_WE)
    add_executable(${TARGET_NAME} ${SRC})
    list(APPEND TARGET_NAMES ${TARGET_NAME})
endforeach()

#
# Dependencies
#
set(ZEDOpenCaptureMac_INCLUDE_DIR /opt/stereolabs/include)
find_library(ZEDOpenCaptureMac_LIB NAMES ZEDOpenCaptureMac PATHS /opt/stereolabs/lib)
find_package(OpenCV REQUIRED)

foreach(TARGET ${TARGET_NAMES})
    target_include_directories(${TARGET}
        PRIVATE
        ${ZEDOpenCaptureMac_INCLUDE_DIR}
        ${OpenCV_INCLUDE_DIRS}
    )

    target_link_libraries(${TARGET}
        PRIVATE
        ${ZEDOpenCaptureMac_LIB}
        ${OpenCV_LIBS}
    )
endforeach()

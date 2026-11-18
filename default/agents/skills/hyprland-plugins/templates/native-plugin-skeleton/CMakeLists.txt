cmake_minimum_required(VERSION 3.16)
project(MyPlugin CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(hyprland CONFIG REQUIRED)

add_library(MyPlugin SHARED src/main.cpp)
target_link_libraries(MyPlugin PRIVATE hyprlib-pluginapi)

install(DIRECTORY ${HYPRLAND_HEADERS_DIR}/src/plugins/ DESTINATION include/
        FILE_SET header FILES ${HYPRLAND_HEADERS_DIR}/src/plugins/PluginAPI.hpp)

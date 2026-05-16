cmake_minimum_required(VERSION 3.16)

project(SteedPilotSim LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(SDL2 REQUIRED)

add_executable(steedpilot-sim
    main.cpp
    SdlDisplay.cpp
    ../src/App.cpp
    ../src/Units.cpp
    ../src/generated/FontAtlas.c
)

target_include_directories(steedpilot-sim PRIVATE
    ../include
    ${SDL2_INCLUDE_DIRS}
)

target_link_libraries(steedpilot-sim PRIVATE ${SDL2_LIBRARIES})

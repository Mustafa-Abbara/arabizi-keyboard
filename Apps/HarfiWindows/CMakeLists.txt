# The Windows keyboard (ADR 0032): a TSF text input processor, HarfiTIP.dll, that loads the shared core
# (HarfiCoreC.dll, built from Packages/ArabiziCore) from its own folder at run time.
cmake_minimum_required(VERSION 3.20)
project(HarfiWindows LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
add_library(HarfiTIP SHARED src/Dll.cpp src/Register.cpp src/TextService.cpp src/Core.cpp src/ChipWindow.cpp src/HarfiTIP.def)
target_include_directories(HarfiTIP PRIVATE include)
target_compile_definitions(HarfiTIP PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN)
target_compile_options(HarfiTIP PRIVATE /W4 /utf-8)
target_link_libraries(HarfiTIP PRIVATE ole32 oleaut32 uuid advapi32 user32 gdi32)

# The Windows keyboard (ADR 0032): a TSF text input processor, HarfiTIP.dll, that loads the shared core
# (HarfiCoreC.dll, built from Packages/ArabiziCore) from its own folder at run time.
cmake_minimum_required(VERSION 3.20)
project(HarfiWindows LANGUAGES CXX RC)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
add_library(HarfiTIP SHARED src/Dll.cpp src/Register.cpp src/TextService.cpp src/Core.cpp src/ChipWindow.cpp
            src/DisplayAttribute.cpp src/Popup.cpp src/PreviewWindow.cpp src/HarfiTIP.def)
target_include_directories(HarfiTIP PRIVATE include)
target_compile_definitions(HarfiTIP PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN)
target_compile_options(HarfiTIP PRIVATE /W4 /utf-8)
target_link_libraries(HarfiTIP PRIVATE ole32 oleaut32 uuid advapi32 user32 gdi32 gdiplus)

# The Harfi window (Welcome, Typing, Your words, Privacy, Help): harfi-settings.exe, installed next to the keyboard.
# It draws with the keyboard's own helpers (Popup.cpp, Theme.h) and reaches the settings and the user's words through
# HarfiCoreC.dll at run time.
add_executable(harfi-settings WIN32 src/settings/Settings.cpp src/Popup.cpp src/settings/harfi.rc)
target_compile_definitions(harfi-settings PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN)
target_compile_options(harfi-settings PRIVATE /W4 /utf-8)
target_link_libraries(harfi-settings PRIVATE user32 gdi32 gdiplus shell32)

# The installer a person double-clicks ("Install Harfi.exe", next to install.ps1 in the package): a window on
# install.ps1, with the model download's progress.
add_executable(harfi-setup WIN32 src/settings/Setup.cpp src/Popup.cpp src/settings/harfi.rc)
set_target_properties(harfi-setup PROPERTIES OUTPUT_NAME "Install Harfi")
target_compile_definitions(harfi-setup PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN)
target_compile_options(harfi-setup PRIVATE /W4 /utf-8)
target_link_libraries(harfi-setup PRIVATE user32 gdi32 gdiplus shell32)

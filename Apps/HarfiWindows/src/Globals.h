// Shared declarations of the Harfi text service (ADR 0032).
#pragma once
#include <windows.h>
#include <msctf.h>
#include <atomic>
#include <string>

// {7164FD3D-2A9F-4AED-9CD1-2C059C40C6E0}: the COM class of the text service.
inline constexpr GUID CLSID_HarfiTextService = {0x7164fd3d, 0x2a9f, 0x4aed, {0x9c, 0xd1, 0x2c, 0x05, 0x9c, 0x40, 0xc6, 0xe0}};
// {94104DFB-A9FC-4FCD-8962-236D0615351C}: its keyboard profile.
inline constexpr GUID GUID_HarfiProfile = {0x94104dfb, 0xa9fc, 0x4fcd, {0x89, 0x62, 0x23, 0x6d, 0x06, 0x15, 0x35, 0x1c}};
// {699AD757-7102-4B0A-BEC2-2FEAB425F976}: the look of the text being typed (underlined).
inline constexpr GUID GUID_HarfiInput = {0x699ad757, 0x7102, 0x4b0a, {0xbe, 0xc2, 0x2f, 0xea, 0xb4, 0x25, 0xf9, 0x76}};
// Arabic (Lebanon): the language of the text Harfi writes.
inline constexpr LANGID HarfiLanguage = MAKELANGID(LANG_ARABIC, SUBLANG_ARABIC_LEBANON);

extern HINSTANCE g_module;
extern std::atomic<long> g_objects;  // live COM objects and locks, for DllCanUnloadNow

// The folder that holds HarfiTIP.dll (and HarfiCoreC.dll and rules\ next to it).
std::wstring ModuleFolder();

// Appends one line to %LOCALAPPDATA%\Harfi\debug.log with the app's name, only when HKCU\Software\Harfi\DebugLog
// is 1. For finding where an app stops loading the keyboard: events only, never what is typed.
void DebugLog(const char *event);

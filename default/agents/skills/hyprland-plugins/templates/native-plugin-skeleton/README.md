# MyPlugin

A minimal Hyprland C++ plugin skeleton.

## Structure

```
myplugin/
├── CMakeLists.txt
├── src/
│   └── main.cpp
└── LICENSE
```

## Content

### CMakeLists.txt

```cmake
cmake_minimum_required(VERSION 3.16)
project(MyPlugin CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(hyprland CONFIG REQUIRED)

add_library(MyPlugin SHARED src/main.cpp)
target_link_libraries(MyPlugin PRIVATE hyprlib-pluginapi)

# Install headers required by the plugin
install(DIRECTORY ${HYPRLAND_HEADERS_DIR}/src/plugins/ DESTINATION include/
        FILE_SET header FILES ${HYPRLAND_HEADERS_DIR}/src/plugins/PluginAPI.hpp)
```

### src/main.cpp

```cpp
#include <hyprland/src/plugins/PluginAPI.hpp>

// Opaque handle pointer (set in PLUGIN_INIT)
inline HANDLE PHANDLE = nullptr;

// 1. API version — DO NOT change. Set by compiler to the right value.
APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

// 2. Init — called when loaded. Store the handle, register features.
APICALL EXPORT PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;

    // Example: add a keybind
    HyprlandAPI::addKeybind(PHANDLE, {
        .description = "MyPlugin: demo keybind",
        .key = {XK_SPACE, MOD_KEY::MASK_COMMAND, MOD_KEY::SUPER},
        .callback = [](PluginAPI::PluginHandle) {
            HyprlandAPI::addNotification(PHANDLE, "[MyPlugin] Space pressed!", 2000);
        },
    });

    // Example: add a callable syscall (hyprctl exec / hyprlandctl)
    HyprlandAPI::addSyscall(PHANDLE, "myplugin/demo", [](PluginAPI::PluginHandle, Event::SyscallEvent& evt) {
        // evt.arguments is a vector<string>; evt.reply() returns a string
        evt.reply("[MyPlugin] demo syscall called");
    });

    return {};
}

// 3. Description
APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INFO() {
    return {"myplugin", "My plugin", "Author", "1.0"};
}

// 4. Exit — called on unload
APICALL EXPORT void PLUGIN_EXIT() {
    // cleanup if needed
}
```

### LICENSE

```
MIT License

Copyright (c) 2026 Author

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Build & load

```bash
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
# Install headers: sudo make installheaders  (only needed once for headers)
# Run the compositor with this plugin
```

Then load from the compositor (or via `hyprctl`):

```bash
hyprctl plugin load /path/to/myplugin.so
hyprctl plugin list
```

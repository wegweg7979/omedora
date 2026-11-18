# Hyprland plugin development references

## Native C++ plugin: minimal template

```cpp
#include <hyprland/src/plugins/PluginAPI.hpp>

inline HANDLE PHANDLE = nullptr;

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;

    // Keybind
    HyprlandAPI::addKeybind(PHANDLE, {
        .description = "Toggle something",
        .key = {XK_SPACE, MOD_KEY::MASK_COMMAND, MOD_KEY::SUPER},
        .callback = [](PluginAPI::PluginHandle) {
            HyprlandAPI::runCommand(PHANDLE, "dispatch some-command");
        },
    });

    // Custom syscall
    HyprlandAPI::addSyscall(PHANDLE, "myplugin/toggle", [](PluginAPI::PluginHandle, Event::SyscallEvent& evt) {
        // parse arguments, reply, etc.
    });

    return {};
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INFO() {
    return {"myplugin", "My plugin", "Author", "1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    // cleanup
}
```

### CMakeLists.txt

```cmake
cmake_minimum_required(VERSION 3.16)
project(MyPlugin CXX)
set(CMAKE_CXX_STANDARD 20)

find_package(hyprland CONFIG REQUIRED)
add_library(MyPlugin SHARED src/main.cpp)
target_link_libraries(MyPlugin PRIVATE hyprlib-pluginapi)
```

## Loading

```bash
hyprctl plugin load /path/to/plugin.so
hyprctl plugin unload /path/to/plugin.so
hyprctl plugin list
```

## Third-party Lua plugins — example structure

```
lua/
├── plugin_name.lua        # entry: exports setup(user_config)
├── plugin_name/
│   ├── module1.lua
│   └── module2.lua
└── test/
    └── plugin_name_spec.lua
```

## Lua plugin manager example (hipe)

```lua
require("hipe").setup({
    spec = {
        "AbaoFromCUG/lua-plugin-template.hypr",
        { "AbaoFromCUG/virtual-desktops.hypr", opts = { initial_count = 2 } },
    },
})
```

## keybind registration in Lua

```lua
-- Simple
hl.bind("SUPER + Q", hl.dsp.exec_cmd("kitty"))

-- With options
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("grim"), {
    repeatable = false,
    description = "Screenshot",
})
```

## Event callbacks

```lua
hl.on("hyprland.start", function()
    print("Hyprland started")
end)

hl.on("config.reloaded", function()
    -- reapply module state on reload
end)
```

## Debugging checklist

1. `hyprctl plugin list` — confirm plugin is loaded
2. `hyprctl configerrors` — config-level errors
3. `hyprctl logbuffer -c` — compositor log (check for load/link errors)
4. `hyprctl logbuffer -m` — monitor log
5. Check `hyprland.log` in `/run/user/$UID/hypr/<sig>/`
6. Verify Hyprland version matches plugin's expectations

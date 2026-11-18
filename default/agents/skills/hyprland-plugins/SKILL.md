---
name: hyprland-plugins
description: "Create native C++ plugins (PluginAPI.hpp) and Lua modules/plugins for Hyprland: structure, plugin managers (hipe, hyprpm), APIs, building, loading, and debugging."
version: 0.1.0
author: Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [hyprland, wayland, lua, cpp, plugin, hyprpm, hipe, hyprctl]
    related_skills: [hyprland-config, quickshell]
---

# Hyprland Plugins Skill

This skill covers creating plugins for **Hyprland** — the Wayland compositor. There are two kinds: **native C++ plugins** (`.so` files with full access to Hyprland internals) and **Lua modules/plugins** (config-driven, hot-reloading, managed by `hipe`/`hyprpm`).

## When to Use

Use this skill when the user asks to:
- Build a native C++ plugin for Hyprland (`hyprctl plugin load`)
- Write a Lua module or Lua plugin for Hyprland (`hl.*` API)
- Install/manage third-party plugins via `hyprpm` or `hipe`
- Debug a plugin that fails to load or crashes Hyprland

## Two kinds of plugins

| Kind | Language | Access | Load path | Use case |
|---|---|---|---|---|
| Native plugin | C++ (`.so`) | Full internal API | `hyprctl plugin load <.so>` | Anything touching Hyprland internals, custom syscalls, extending the compositor |
| Lua module / plugin | Lua | `hl.*` limited API | `hl.plugin.load()` or `hipe`/`hyprpm` | UI hooks, config-driven additions, lighter integrations |

## Native C++ plugins

### Overview

Native plugins are compiled shared objects (`.so`) that Hyprland loads at runtime. They get (almost) full access to Hyprland's internal process: windows, workstations, input, render, syscalls, etc.

### Required boilerplate

Every plugin needs these symbols:

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
    // ... register keybinds, syscalls, windows, etc.
    return {};
}

// 3. Description — name, description, author, version
APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INFO() {
    return {"MyPlugin", "An amazing plugin", "Author", "1.0"};
}

// 4. Exit — called on unload
APICALL EXPORT void PLUGIN_EXIT() {
    // cleanup
}
```

### Build system (CMakeLists.txt)

```cmake
cmake_minimum_required(VERSION 3.16)
project(MyPlugin CXX)

set(CMAKE_CXX_STANDARD 20)

find_package(hyprland CONFIG REQUIRED)
add_library(MyPlugin SHARED src/main.cpp)
target_link_libraries(MyPlugin PRIVATE hyprlib-pluginapi)
```

### Load & unload

```bash
hyprctl plugin load /absolute/path/to/plugin.so     # load
hyprctl plugin unload /absolute/path/to/plugin.so   # unload
hyprctl plugin list                                 # list loaded plugins
```

### Plugin API — key namespaces

From `PluginAPI.hpp` and `PluginAPIFunctions.hpp`:

- `HyprlandAPI::addNotification(HANDLE, text, duration)` — show a notification
- `HyprlandAPI::addKeybind(HANDLE, KeybindConfig)` — register a keybind
- `HyprlandAPI::addSyscall(HANDLE, name, fn)` — expose a custom command via `hyprctl` / `hyprlandctl`
- `HyprlandAPI::addWindowHook(HANDLE, WindowHook)` — react to window create/destroy/close/activate
- `HyprlandAPI::addRenderHook(HANDLE, RenderHook)` — hook the render chain
- `HyprlandAPI::getWindows(HANDLE)` / `getActiveWindow(HANDLE)` — window enumeration
- `HyprlandAPI::runCommand(HANDLE, cmd)` — execute a Hyprland dispatch command
- `HyprlandAPI::getConfigValue(HANDLE, key)` — read a config value
- `HyprlandAPI::registerPluginSettings(HANDLE, ...)` — expose `hyprctl setoption hyprland <plugin.name>.key value` settings

### Example: plugin with a keybind + syscall

```cpp
#include <hyprland/src/plugins/PluginAPI.hpp>

inline HANDLE PHANDLE = nullptr;

APICALL EXPORT std::string PLUGIN_API_VERSION() { return HYPRLAND_API_VERSION; }

APICALL EXPORT PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;
    HyprlandAPI::addKeybind(PHANDLE, {
        .description = "My plugin: toggle something",
        .key = {XK_SPACE, MOD_KEY::MASK_COMMAND, MOD_KEY::SUPER},
        .callback = [](PluginAPI::PluginHandle) {
            HyprlandAPI::runCommand(PHANDLE, "dispatch some-command");
        },
    });
    HyprlandAPI::addSyscall(PHANDLE, "myplugin/toggle", [](PluginAPI::PluginHandle, Event::SyscallEvent& evt) {
        // evt.arguments, evt.reply() ...
    });
    return {};
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INFO() {
    return {"myplugin", "My plugin", "Me", "1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {}
```

### Building native plugins

```bash
git clone https://github.com/hyprwm/Hyprland
cd Hyprland
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
# headers installed via: sudo make installheaders
```

> Headless development: `/etc/hypr` or a separate config dir; launch `./build/hyprland` in a live session. Use `hyprctl exec` to run commands.

## Lua modules & plugins (modern, Hyprland ≥ 0.55)

### Overview

Since Hyprland 0.55+, plugins can be written in Lua. They use the `hl.*` API and are typically configured in `~/.config/hypr/hyprland.lua` + a `modules/` directory. They hot-reload with the config.

### Lua API — `hl.*` namespace

Key functions:

| Function | Purpose |
|---|---|
| `hl.config({})` | Global config (general, decoration, animations, input, misc) |
| `hl.monitor({})` | Monitor rules (resolution, position, scale, on Workspace) |
| `hl.bind(key, action, opts)` | Keybinding |
| `hl.unbind(key)` | Remove a binding |
| `hl.env(name, value)` | Environment variable |
| `hl.gesture({})` | Touchpad gestures |
| `hl.window_rule({})` | Window rules (match, border_size, animations, etc.) |
| `hl.workspace_rule({})` | Workspace rules |
| `hl.layer_rule({})` | Layer rules (overlay, etc.) |
| `hl.on("hyprland.start", fn)` | Run after startup |
| `hl.on("config.reloaded", fn)` | Run on config reload |
| `hl.dsp` | Dispatcher namespace: `exec_cmd`, `focus`, `window`, `layout`, `workspace` |

### Module structure

```
~/.config/hypr/
├── hyprland.lua      # entry point
├── modules/
│   ├── monitors.lua  # display config
│   ├── input.lua     # keyboard/mouse
│   ├── appearance.lua# gaps, borders, blur
│   ├── animations.lua# bezier animations
│   ├── plugins.lua   # load third-party Lua plugins
│   └── binds.lua     # keybinds
```

Entry point (`hyprland.lua`):
```lua
-- Set this to false to not load Omarchy defaults
omarchy_default_bindings = false

-- Require modules
for _, mod in ipairs({"monitors", "input", "bindings", "appearance"}) do
    local ok, err = pcall(require, "modules." .. mod)
    if not ok then print("Failed to load module " .. mod .. ": " .. tostring(err)) end
end

-- Configure third-party Lua plugins
hl.plugin.load("/path/to/plugin.lua", { opts = {} })
```

### Hot-reload & error handling

- Config is reloaded on save; use `hyprctl reload` to apply.
- Use `pcall(require, ...)` for optional modules so a broken module doesn't block the whole config.
- Use `hl.on("config.reloaded", ...)` to reapply per-module state on reload.

## Plugin managers

### hipe (Hyprland Plugin Manager) — `lazy.nvim`-style

`hipe` is a plugin manager for Hyprland Lua plugins. It handles cloning, ordering, `package.path` setup, config callbacks, keybind registration, and optional LuaRocks dependencies.

```lua
require("hipe").setup({
    spec = {
        "AbaoFromCUG/lua-plugin-template.hypr",
        { "AbaoFromCUG/virtual-desktops.hypr", opts = { initial_count = 2 } },
    },
})
```

Convention: `lua/plugin_name.lua` (entry, exports `setup(user_config)`), `lua/plugin_name/*.lua` (submodules), `test/*_spec.lua` (busted-style via `hipe.test.runner`).

### hyprpm (Hyprland RPM / plugin manager) — official

`hyprpm` is Hyprland's official plugin manager. It installs plugins from GitHub repos as shared objects or Lua modules.

```bash
hyprpm install <owner/repo>      # install a plugin
hyprpm update                      # update all
hyprpm uninstall <owner/repo>      # uninstall
hyprpm list                        # list installed
```

Plugins are typically loaded via config:
```lua
hl.plugin.load("/run/hypr/hyprpm/<plugin>/plugin.so")
```

## Debugging & triage

| Symptom | Likely cause | Check |
|---|---|---|
| `.so` fails to load | Header mismatch, wrong ABI, missing dep | `hyprctl plugin list`; check `hyprland.log` |
| Lua plugin errors | Syntax, missing `hl.*`, pcall failure | `~/.config/hypr/hyprland.log` / `hyprctl configerrors` |
| Plugin loads but no effect | Registering to wrong scope, wrong event timing | Use `hl.on("hyprland.start")` or `hyprctl` debug |
| Crashes on load | API version mismatch, accessing freed memory | Compile against matching Hyprland version; check `hyprland.log` |

### Debug tools

```bash
hyprctl plugin list                    # loaded plugins
hyprctl configerrors                   # config-level errors
hyprctl logbuffer -c                   # Hyprland log (tail)
hyprctl logbuffer -m                     # monitor log
```

## Guidelines

### Do
- Pin the Hyprland version: native plugins break on API changes; Lua plugins on `hl.*` changes.
- Register keybinds in `PLUGIN_INIT` or use `hl.on("hyprland.start", ...)` for Lua.
- Use `hyprctl` for integration with existing compositor features (dispatch, window ops).
- For native plugins: use `addSyscall` for commands, `addKeybind` for keybinds, `addNotification` for feedback.
- Use `qt` QtQuick for any UI overlays (see quickshell skill).

### Don't
- Don't ship native plugins without testing with the target Hyprland version.
- Don't rely on the deprecated `misc:` options unless documented.
- Don't edit `hyprland.lua` that ships in packages — it's overwritten on update.

## References

- [Hyprland Wiki — Plugins](https://wiki.hypr.land/)
- [Getting started — Plugin development](https://wiki.hypr.land/hyprland-plugins/development/getting-started/) — native C++ plugin tutorial
- [Hyprland Lua API Reference](https://alejandrominaya.github.io/hyprland-lua-docs/) — `hl.*` docs
- [HyprlandLua GitHub](https://github.com/victorsosaMx/HyprlandLUA) — community Lua config template
- [hipe — Hyprland plugin manager](https://github.com/hyprwm/hipe) — `lazy.nvim`-style plugin manager
- [hyprpm — Hyprland plugin manager](https://wiki.hypr.land/hyprpm/) — official plugin manager
- `templates/native-plugin-skeleton/` — copy-paste starter for a new native plugin (CMakeLists.txt + main.cpp + LICENSE)

## Template

A copy-paste native plugin skeleton is at [`templates/native-plugin-skeleton/`](templates/native-plugin-skeleton/), with `CMakeLists.txt`, `src/main.cpp`, and `LICENSE`.

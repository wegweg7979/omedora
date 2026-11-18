#include <hyprland/src/plugins/PluginAPI.hpp>

// Opaque handle pointer (set in PLUGIN_INIT)
inline HANDLE PHANDLE = nullptr;

// 1. API version — DO NOT change. Set by the compiler to the right value.
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

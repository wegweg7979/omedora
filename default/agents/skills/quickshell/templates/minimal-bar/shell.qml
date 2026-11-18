# Minimal Quickshell bar

A minimal working Quickshell config that displays a clock and a workspace indicator.
Copy this to `~/.config/quickshell/mybar/shell.qml` and run with:

```bash
qs -c mybar
```

## file: shell.qml

```qml
import QtQuick 6.0
import QtQuick.Controls 6.0
import QtQuick.Layouts 6.0

Item {
    id: root
    width: 800
    height: 32

    // Dynamic properties
    property color barColor: '#1f2328'
    property int clockInterval: 1000

    // Clock text with live update
    Text {
        id: clockText
        text: DateTime.format(Qt.formatTime(), new Date(), "hh:mm:ss")
        anchors {
            horizontalCenter: parent.horizontalCenter
            verticalCenter: parent.verticalCenter
        }
        color: '#ffffff'
        font.pointSize: 14
    }

    // Workspace indicator (updates on config reload)
    Text {
        id: workspaceText
        text: "WS " + Hyprland.getWorkspace()
        anchors {
            horizontalCenter: parent.horizontalCenter
            verticalCenter: parent.verticalCenter
            left: clockText.right
            margins: 8
        }
        color: '#8b949e'
        font.pointSize: 14
    }

    // Auto-refresh clock every second
    Timer {
        interval: clockInterval
        running: true
        repeat: true
        onTriggered: {
            clockText.text = DateTime.format(Qt.formatTime(), new Date(), "hh:mm:ss")
        }
    }
}
```

## Notes

- `qs -c mybar` reads `$XDG_CONFIG_HOME/quickshell/mybar/shell.qml`
- If you run from a terminal (not daemonized), changes hot-reload automatically.
- Use `qs -v` to see internals while debugging.
- For more QML patterns, see the `references/quickshell-qml-reference.md` skill file.

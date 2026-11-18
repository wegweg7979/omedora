# Quickshell QML reference examples

Minimal bar config structure:

```qml
import QtQuick 6.0
import QtQuick.Controls 6.0

Item {
    id: root
    width: 800
    height: 32

    // Dynamic properties
    property color barColor: '#1f2328'
    property int clockInterval: 1000 // update every second

    // Text + clock binding
    Text {
        id: clockText
        text: DateTime.format(Qt.formatTime(), new Date(), "hh:mm")
        anchors.centerIn: parent
        color: '#ffffff'
    }
}
```

## Key QML facts

### Imports
```qml
import QtQuick 6.0
import QtQuick.Controls 6.0   // buttons, sliders, etc.
import QtQuick.Layouts 6.0    // RowLayout, ColumnLayout
import "myjs.js" as MyJs      // JS module (hot-reloads)
```

### Properties & bindings
```qml
Item {
    property string label: "hello"
    property color myColor: '#ff0000'
    property int count: 0

    width: 200
    height: 50
    color: myColor
}
```

### Signals
```qml
Item {
    signal clicked()
    signal valueChanged(int newValue)

    MouseArea {
        anchors.fill: parent
        onClicked: { clicked(); valueChanged(42) }
    }
}
```

### Attached property handlers
```qml
Component.onCompleted: console.log("ready")
Component.onDestruction: console.log("cleanup")
```

### Layout (QML scene graph — not CSS)
```qml
Item {
    width: 600; height: 100
    Row {
        spacing: 8
        anchors.fill: parent
        anchors margins: 4
        Text { id: a; text: "A" }
        Text { id: b; text: "B" }
    }
}
```

Use `Layout.fillWidth`, `Layout.preferredWidth`, `Layout.minimumWidth`
on children for responsive sizing.

## Extensions

### QtQuick.Controls
- `Button`, `Slider`, `Label`, `CheckBox`, `ComboBox`, `ToolTip`

### QtQuick.Layouts
- `RowLayout`, `ColumnLayout`, `GridLayout` with `Layout.*` attached props

## Debugging

```bash
# Run with debug port
quickshell -c myconfig --debug 1234 --waitfordebug

# Attach QML inspector (Qt Creator or a QML debugging tool)

# Logs
quickshell log -c myconfig

# IPC
quickshell ipc call <other-config-name> "hello"
quickshell ipc subscribe "mytopic"
quickshell ipc unsubscribe "mytopic"
```

# NetworkManager over D-Bus — working recipes

Verified against NetworkManager 1.58 / wpa_supplicant 2.11 on Fedora 45, on an
Intel AX210 (`wlp4s0`). C++ is Qt 6 (`QT += dbus`); the same shapes work from
`qdbus6` for one-off inspection.

## Quick recon without writing code

```sh
nmcli -t -f DEVICE,TYPE,STATE device status          # find the wifi interface
nmcli -f SSID,BSSID,CHAN,FREQ,RATE,SIGNAL,BARS,SECURITY dev wifi list --rescan yes
iw dev                                                # interface, current channel, width
iw phy phy0 info                                      # band plan (Band 1/2/4 + channels)
iw reg get                                            # global and phy-managed regulatory state
```

`nmcli --rescan yes` works unprivileged in ~4.5 s with no polkit prompt. It gives
no channel width and no noise. There is no Python `dbus`/`gi` on these hosts, so
shell or compiled Qt is the practical route.

Its output uses **decimal** frequencies (`2412.0 MHz [1]`), so any awk over
`iw phy` must match `[0-9.]+ MHz`, not `[0-9]+ MHz` — a `[0-9]+` pattern silently
counts zero channels for every band.

## The two unwrapping traps

`Properties.GetAll` wraps every value in a `QDBusVariant`, and an `ao` property
arrives as a `QDBusArgument`. Read either without unwrapping and every field
comes back empty — with no error anywhere.

```cpp
QVariant unwrap(QVariant value) {
    if (value.metaType().id() == qMetaTypeId<QDBusVariant>())
        value = value.value<QDBusVariant>().variant();
    return value;
}

QVariantMap propertiesOf(const QString &path, const QString &iface) {
    QVariantMap result;
    QDBusInterface properties("org.freedesktop.NetworkManager", path,
                              "org.freedesktop.DBus.Properties", QDBusConnection::systemBus());
    const QDBusReply<QVariantMap> reply = properties.call("GetAll", iface);
    if (!reply.isValid())
        return result;
    const QVariantMap raw = reply.value();
    for (auto it = raw.cbegin(); it != raw.cend(); ++it)
        result.insert(it.key(), unwrap(it.value()));
    return result;
}
```

## Device and access points

```cpp
// Wi-Fi devices are the ones with DeviceType == 2 (NM_DEVICE_TYPE_WIFI).
QDBusReply<QList<QDBusObjectPath>> devices = manager.call("GetDevices");

// The access-point list: the method first (it demarshals cleanly), then the
// property, which needs the QDBusArgument read out by hand.
QDBusReply<QList<QDBusObjectPath>> byMethod = wireless.call("GetAccessPoints");
QVariant raw = propertiesOf(devicePath, kWifiIface).value("AccessPoints");
QList<QDBusObjectPath> paths;
if (raw.metaType().id() == qMetaTypeId<QDBusArgument>())
    raw.value<QDBusArgument>() >> paths;
```

Access points have a trailing `/1`, `/2`… in their object path, which is handy
for reading a log line but means nothing stable across scans — key by `HwAddress`.

## Scan request, and proving it ran

```cpp
QDBusInterface wireless(service, devicePath, "org.freedesktop.NetworkManager.Device.Wireless", bus);
QDBusReply<void> reply = wireless.call("RequestScan", QVariantMap());  // returns ~2 ms

// Freshness: LastScan only moves when a scan really completed.
const qlonglong stamp = propertiesOf(devicePath, kWifiIface).value("LastScan").toLongLong();
if (m_previous != 0 && stamp != m_previous) m_scanCompleted = true;
m_previous = stamp;
```

## Per-access-point signal watcher

A small `Q_OBJECT` trampoline per AP path, defined in the `.cpp`. The trailing
`#include` is what makes moc process the file — without it the connects fail at
**runtime** with no build error.

```cpp
class NmApWatcher : public QObject {
    Q_OBJECT
public:
    explicit NmApWatcher(NmWifiSource *source, QObject *parent = nullptr)
        : QObject(parent), m_source(source) {}
    void listen(const QString &apPath) {
        QDBusConnection::systemBus().connect(
            "org.freedesktop.NetworkManager", apPath, "org.freedesktop.DBus.Properties",
            "PropertiesChanged", this, SLOT(onPropertiesChanged(QString,QVariantMap,QStringList)));
    }
public slots:
    void onPropertiesChanged(const QString &, const QVariantMap &changed, const QStringList &) {
        if (changed.contains("Strength") || changed.contains("LastSeen"))
            emit m_source->changed();          // let the owner re-read and re-render
    }
private:
    NmWifiSource *m_source;
};
```

Watch per-AP paths in a `QHash<QString, NmApWatcher*>` and prune on
`AccessPointRemoved`; `std::as_const` over the hash before deleting.

## The other useful signals

Connect `AccessPointAdded` / `AccessPointRemoved` on the device with the
receiver's own `changed()` signal as the slot string
(`bus.connect(service, path, iface, "AccessPointAdded", this, SLOT(changed()))`)
— structural changes then cost no polling. NetworkManager pushes nothing at all
when nothing changed, so a quiet window is not evidence of a quiet air.

## Sanity checks worth keeping in the tool

- Associated AP: the device's `ActiveAccessPoint` (`o`) → that AP's `HwAddress`.
- Wi-Fi switched off: the root `org.freedesktop.NetworkManager` object's
  `WirelessEnabled` property — report it as a blocker rather than showing an
  empty table.
- `WirelessEnabled == false`, no wifi device, and "NetworkManager is not
  running" are three different messages; the window should say which one.

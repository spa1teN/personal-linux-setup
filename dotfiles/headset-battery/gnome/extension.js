import St from 'gi://St';
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import GObject from 'gi://GObject';
import Clutter from 'gi://Clutter';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';

const POLL_SECONDS = 60;
// apt installs to /usr/bin, source builds to /usr/local/bin; probe both since
// gnome-shell has a minimal PATH.
const HEADSETCONTROL_PATH = (() => {
    for (const p of ['/usr/local/bin/headsetcontrol', '/usr/bin/headsetcontrol']) {
        if (GLib.file_test(p, GLib.FileTest.IS_EXECUTABLE))
            return p;
    }
    return GLib.find_program_in_path('headsetcontrol');
})();
const ICON_SIZE = 20;

// Known Bluetooth headset
const BT_ADDRESS = '2C:41:A1:4E:F8:9D';
const BT_NAME = 'spa1teN headphones';
const BT_PATH = '/org/bluez/hci0/dev_' + BT_ADDRESS.replace(/:/g, '_');

const HeadsetBatteryIndicator = GObject.registerClass(
class HeadsetBatteryIndicator extends PanelMenu.Button {
    _init(extPath) {
        super._init(0.0, 'Headset Battery', false);

        this._extPath = extPath;
        this._micConnected = true;

        // Box containing icon + percentage label with a small gap
        this._box = new St.BoxLayout({ style_class: 'panel-status-menu-box' });
        this._icon = new St.Icon({
            icon_size: ICON_SIZE,
            y_align: Clutter.ActorAlign.CENTER,
        });
        this._box.add_child(this._icon);

        this._label = new St.Label({
            y_align: Clutter.ActorAlign.CENTER,
            style: 'margin-left: 4px',
        });
        this._label.clutter_text.set_text('…');
        this._box.add_child(this._label);

        this.add_child(this._box);

        this._deviceItem = new PopupMenu.PopupMenuItem('Device: …', { reactive: false });
        this.menu.addMenuItem(this._deviceItem);

        this._statusItem = new PopupMenu.PopupMenuItem('Updating…', { reactive: false });
        this.menu.addMenuItem(this._statusItem);

        // Manual mic toggle — hardware does not always expose physical mic presence
        this._micSwitch = new PopupMenu.PopupSwitchMenuItem('Mic connected', true);
        this._micSwitch.connect('toggled', (item) => {
            this._micConnected = item.state;
            this._refresh();
        });
        this.menu.addMenuItem(this._micSwitch);

        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        const refreshItem = new PopupMenu.PopupMenuItem('Refresh now');
        refreshItem.connect('activate', () => this._refresh());
        this.menu.addMenuItem(refreshItem);

        // Start hidden — only show when a headset is connected
        this.visible = false;

        this._timeoutId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, POLL_SECONDS, () => {
            this._refresh();
            return GLib.SOURCE_CONTINUE;
        });
        this._refresh();
    }

    // --- Bluetooth (BlueZ D-Bus) --------------------------------------------

    _getBluetoothBattery() {
        try {
            const conn = Gio.DBus.system;

            // Check if device is connected
            const connectedResult = conn.call_sync(
                'org.bluez',
                BT_PATH,
                'org.freedesktop.DBus.Properties',
                'Get',
                new GLib.Variant('(ss)', ['org.bluez.Device1', 'Connected']),
                null,
                Gio.DBusCallFlags.NONE,
                -1,
                null
            );
            const [connected] = connectedResult.get_child_value(0).deepUnpack();
            if (!connected) return null;

            // Get battery percentage
            const batResult = conn.call_sync(
                'org.bluez',
                BT_PATH,
                'org.freedesktop.DBus.Properties',
                'Get',
                new GLib.Variant('(ss)', ['org.bluez.Battery1', 'Percentage']),
                null,
                Gio.DBusCallFlags.NONE,
                -1,
                null
            );
            const [level] = batResult.get_child_value(0).deepUnpack();

            return { device: BT_NAME, level, charging: false, source: 'bluetooth' };
        } catch (e) {
            return null;
        }
    },

    // --- headsetcontrol (USB/HID headsets) ----------------------------------

    _refreshHeadsetControl() {
        try {
            const proc = Gio.Subprocess.new(
                [HEADSETCONTROL_PATH, '-o', 'JSON', '-b'],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE
            );
            proc.communicate_utf8_async(null, null, (proc_, res) => {
                try {
                    const [, stdout] = proc_.communicate_utf8_finish(res);
                    this._applyHeadsetControl(stdout);
                } catch (e) {
                    this._setError();
                }
            });
        } catch (e) {
            this._setError();
        }
    },

    // --- Main refresh -------------------------------------------------------

    _refresh() {
        // Try Bluetooth first; fall back to headsetcontrol
        const bt = this._getBluetoothBattery();
        if (bt) {
            this._applyDevice(bt);
        } else {
            this._refreshHeadsetControl();
        }
    },

    _applyHeadsetControl(stdout) {
        let data;
        try {
            data = JSON.parse(stdout);
        } catch (e) {
            this._setError();
            return;
        }

        const device = data.devices && data.devices[0];
        if (!device || device.status !== 'success' || !device.battery || device.battery.level < 0) {
            this._setOffline();
            return;
        }

        this._applyDevice({
            device: device.product || 'USB headset',
            level: device.battery.level,
            charging: device.battery.status === 'BATTERY_CHARGING',
            source: 'usb',
        });
    },

    _applyDevice(info) {
        const level = info.level;
        const charging = info.charging;

        this._setIcon(this._micConnected);
        this._label.clutter_text.set_text(`${level}%`);

        if (charging) {
            this._label.set_style('color: #00cc00; margin-left: 4px');
        } else {
            this._label.set_style('margin-left: 4px');
        }

        this.visible = true;

        const now = GLib.DateTime.new_now_local().format('%H:%M:%S');
        const micStr = this._micConnected ? 'mic on' : 'mic off';
        const chargeStr = charging ? ' (charging)' : '';
        this._deviceItem.label.text = `Device: ${info.device}`;
        this._statusItem.label.text = `${level}%${chargeStr} — ${micStr} — updated ${now}`;
    },

    // --- Icon switching -----------------------------------------------------

    _setIcon(micOn) {
        const name = micOn ? 'with-mic.png' : 'without-mic.png';
        const path = GLib.build_filenamev([this._extPath, name]);
        const file = Gio.File.new_for_path(path);
        this._icon.gicon = Gio.FileIcon.new(file);
    },

    // --- Offline / error states ---------------------------------------------

    _setOffline() {
        this.visible = false;
        this._deviceItem.label.text = 'Device: none';
        this._statusItem.label.text = 'No headset connected';
    },

    _setError() {
        this._setIcon(false);
        this._label.clutter_text.set_text('?');
        this._label.set_style('margin-left: 4px');
        this.visible = true;
        this._deviceItem.label.text = 'Device: ?';
        this._statusItem.label.text = 'headsetcontrol not found or failed';
    },

    stop() {
        if (this._timeoutId) {
            GLib.source_remove(this._timeoutId);
            this._timeoutId = null;
        }
    }
});

export default class HeadsetBatteryExtension extends Extension {
    enable() {
        this._indicator = new HeadsetBatteryIndicator(this.path);
        Main.panel.addToStatusArea('headset-battery', this._indicator, 1);
    }

    disable() {
        this._indicator.stop();
        this._indicator.destroy();
        this._indicator = null;
    }
}

const Applet = imports.ui.applet;
const GLib = imports.gi.GLib;
const Gio = imports.gi.Gio;
const PopupMenu = imports.ui.popupMenu;
const Mainloop = imports.mainloop;

const POLL_SECONDS = 60;
const HEADSETCONTROL_PATH = '/usr/local/bin/headsetcontrol';

// Known Bluetooth headset
const BT_ADDRESS = '2C:41:A1:4E:F8:9D';
const BT_NAME = 'spa1teN headphones';
const BT_PATH = '/org/bluez/hci0/dev_' + BT_ADDRESS.replace(/:/g, '_');

function HeadsetBatteryApplet(metadata, orientation, panel_height, instance_id) {
    this._init(metadata, orientation, panel_height, instance_id);
}

HeadsetBatteryApplet.prototype = {
    __proto__: Applet.TextIconApplet.prototype,

    _init: function(metadata, orientation, panel_height, instance_id) {
        Applet.TextIconApplet.prototype._init.call(this, orientation, panel_height, instance_id);

        this._extPath = metadata.path;
        this._micConnected = true;
        this.set_applet_tooltip('Headset Battery');

        this._menuManager = new PopupMenu.PopupMenuManager(this);
        this.menu = new Applet.AppletPopupMenu(this, orientation);
        this._menuManager.addMenu(this.menu);

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

        let refreshItem = new PopupMenu.PopupMenuItem('Refresh now');
        refreshItem.connect('activate', () => this._refresh());
        this.menu.addMenuItem(refreshItem);

        // Small gap between icon and percentage label
        this._applet_label.set_style('margin-left: 4px');

        // Start hidden — only show when a headset is connected
        this.actor.hide();

        this._timeoutId = Mainloop.timeout_add_seconds(POLL_SECONDS, () => {
            this._refresh();
            return true;
        });
        this._refresh();
    },

    on_applet_clicked: function() {
        this.menu.toggle();
    },

    // --- Bluetooth (BlueZ D-Bus) --------------------------------------------

    _getBluetoothBattery: function() {
        try {
            let conn = Gio.DBus.system;

            // Check if device is connected
            let connectedResult = conn.call_sync(
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
            let connectedVariant = connectedResult.get_child_value(0);
            let [connected] = connectedVariant.deepUnpack();
            if (!connected) return null;

            // Get battery percentage
            let batResult = conn.call_sync(
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
            let batVariant = batResult.get_child_value(0);
            let [level] = batVariant.deepUnpack();

            return { device: BT_NAME, level: level, charging: false, source: 'bluetooth' };
        } catch (e) {
            return null;
        }
    },

    // --- headsetcontrol (USB/HID headsets) ----------------------------------

    _refreshHeadsetControl: function() {
        try {
            let proc = Gio.Subprocess.new(
                [HEADSETCONTROL_PATH, '-o', 'JSON', '-b'],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE
            );
            proc.communicate_utf8_async(null, null, (proc_, res) => {
                try {
                    let [, stdout] = proc_.communicate_utf8_finish(res);
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

    _refresh: function() {
        // Try Bluetooth first; fall back to headsetcontrol
        let bt = this._getBluetoothBattery();
        if (bt) {
            this._applyDevice(bt);
        } else {
            this._refreshHeadsetControl();
        }
    },

    _applyHeadsetControl: function(stdout) {
        let data;
        try {
            data = JSON.parse(stdout);
        } catch (e) {
            this._setError();
            return;
        }

        let device = data.devices && data.devices[0];
        if (!device || device.status !== 'success' || !device.battery || device.battery.level < 0) {
            this._setOffline();
            return;
        }

        this._applyDevice({
            device: device.product || 'USB headset',
            level: device.battery.level,
            charging: device.battery.status === 'BATTERY_CHARGING',
            source: 'usb'
        });
    },

    _applyDevice: function(info) {
        let level = info.level;
        let charging = info.charging;

        this._setIcon(this._micConnected);
        this._applet_label.set_text(`${level}%`);

        if (charging) {
            this._applet_label.set_style('color: #00cc00; margin-left: 4px');
        } else {
            this._applet_label.set_style('margin-left: 4px');
        }

        this.actor.show();

        let now = GLib.DateTime.new_now_local().format('%H:%M:%S');
        let micStr = this._micConnected ? 'mic on' : 'mic off';
        let chargeStr = charging ? ' (charging)' : '';
        this._deviceItem.label.text = `Device: ${info.device}`;
        this._statusItem.label.text = `${info.level}%${chargeStr} — ${micStr} — updated ${now}`;
    },

    // --- Icon switching -----------------------------------------------------

    _setIcon: function(micOn) {
        let name = micOn ? 'with-mic.png' : 'without-mic.png';
        let path = GLib.build_filenamev([this._extPath, name]);
        this.set_applet_icon_path(path);
    },

    // --- Offline / error states ---------------------------------------------

    _setOffline: function() {
        this.actor.hide();
        this._deviceItem.label.text = 'Device: none';
        this._statusItem.label.text = 'No headset connected';
    },

    _setError: function() {
        this._setIcon(false);
        this._applet_label.set_text('?');
        this._applet_label.set_style('margin-left: 4px');
        this.actor.show();
        this._deviceItem.label.text = 'Device: ?';
        this._statusItem.label.text = 'headsetcontrol not found or failed';
    },

    on_applet_removed_from_panel: function() {
        if (this._timeoutId) {
            Mainloop.source_remove(this._timeoutId);
            this._timeoutId = null;
        }
    }
};

function main(metadata, orientation, panel_height, instance_id) {
    return new HeadsetBatteryApplet(metadata, orientation, panel_height, instance_id);
}

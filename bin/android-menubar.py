#!/opt/homebrew/bin/python3.13
# -*- coding: utf-8 -*-
"""
Icono de barra de menús para Espejo Android: conexión WiFi BAJO DEMANDA.

- El modo USB no pasa por aquí: sigue siendo 100% automático (el watcher).
- Este icono solo dispara/corta la conexión inalámbrica: hace `adb connect`
  a la IP que el watcher memorizó (~/.espejo-wifi) la última vez que el
  teléfono estuvo por cable; al aparecer el device, el watcher hace el resto
  (espejo + barra + tapa), exactamente igual que por USB.
- Lo mantiene vivo el LaunchAgent com.stevenson.espejo-menubar.
"""
import os
import subprocess
import threading

from Foundation import NSObject
from AppKit import (NSApplication, NSApplicationActivationPolicyAccessory,
                    NSImage, NSMenu, NSMenuItem, NSStatusBar,
                    NSVariableStatusItemLength)

ADB = "/opt/homebrew/bin/adb"
STATE_FILE = os.path.expanduser("~/.espejo-wifi")   # "IP SERIAL" (lo escribe el watcher)


def sh(*args, timeout=10):
    try:
        return subprocess.run(list(args), capture_output=True, text=True,
                              timeout=timeout).stdout
    except Exception:
        return ""


def devices():
    # [(serial, es_wifi), ...] solo los autorizados
    out = []
    for line in sh(ADB, "devices").splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 2 and parts[1] == "device":
            out.append((parts[0], ":" in parts[0]))
    return out


def saved_target():
    try:
        with open(STATE_FILE) as f:
            ip = f.read().split()[0]
            return f"{ip}:5555" if ip else None
    except Exception:
        return None


def notify(msg, title="Espejo Android"):
    subprocess.run(["osascript", "-e",
                    f'display notification "{msg}" with title "{title}"'],
                   capture_output=True)


class MenuController(NSObject):

    # --- refrescar el menú justo antes de mostrarse -------------------------
    def menuNeedsUpdate_(self, menu):
        devs = devices()
        wifi = [s for s, w in devs if w]
        usb = [s for s, w in devs if not w]
        if usb:
            estado = "Conectado por USB 🔌"
        elif wifi:
            estado = "Conectado por WiFi 📶"
        else:
            estado = "Sin conexión"
        self.status_item.setTitle_(estado)
        self.connect_item.setEnabled_(not devs and saved_target() is not None)
        if not saved_target():
            self.connect_item.setTitle_("Conectar por WiFi (primero una vez por cable)")
        else:
            self.connect_item.setTitle_("Conectar espejo por WiFi")
        self.disconnect_item.setHidden_(not wifi)

    # --- feedback visible junto al icono (las notificaciones pueden estar
    # silenciadas por macOS, así que el estado se muestra en la propia barra)
    def setBadge_(self, text):
        item.button().setTitle_(text or "")

    def pushBadge_(self, text):
        self.performSelectorOnMainThread_withObject_waitUntilDone_(
            "setBadge:", text, False)

    # --- acciones ------------------------------------------------------------
    def connectWifi_(self, sender):
        threading.Thread(target=self._connect, daemon=True).start()

    def _connect(self):
        target = saved_target()
        if not target:
            self.pushBadge_(" sin teléfono memorizado")
            notify("Conecta el teléfono por cable una vez para memorizarlo")
            return
        self.pushBadge_(" buscando…")
        out = sh(ADB, "connect", target, timeout=8)
        if "connected" in out:                 # "connected to" / "already connected"
            self.pushBadge_("")
            notify("Teléfono encontrado — abriendo el espejo…")
            return
        # ¿cambió la IP? intentar redescubrirlo por mDNS
        for line in sh(ADB, "mdns", "services", timeout=6).splitlines():
            parts = line.split()
            if len(parts) >= 3 and "_adb._tcp" in parts[1] and ":" in parts[-1]:
                out = sh(ADB, "connect", parts[-1], timeout=8)
                if "connected" in out:
                    self.pushBadge_("")
                    ip = parts[-1].split(":")[0]
                    try:                        # memorizar la IP nueva
                        with open(STATE_FILE) as f:
                            ser = (f.read().split() + [""])[1]
                        with open(STATE_FILE, "w") as f:
                            f.write(f"{ip} {ser}")
                    except Exception:
                        pass
                    notify("Teléfono encontrado (IP nueva) — abriendo el espejo…")
                    return
        self.pushBadge_(" no lo encuentro (¿misma red WiFi?)")
        notify("No encontré el teléfono en esta red. ¿Mismo WiFi? "
               "Si reiniciaste el teléfono, conéctalo por cable una vez.")
        import time as _t; _t.sleep(6)
        self.pushBadge_("")

    def disconnectWifi_(self, sender):
        threading.Thread(target=self._disconnect, daemon=True).start()

    def _disconnect(self):
        # des-engañar la tapa ANTES de cortar (sin cable no hay sysfs; así el
        # cover revive ya y no en los ~12s del latido). Inofensivo si no aplica.
        for ser, wifi in devices():
            if wifi:
                sh(ADB, "-s", ser, "shell", "cmd", "device_state", "state", "reset",
                   timeout=5)
                sh(ADB, "disconnect", ser, timeout=5)
        notify("Espejo WiFi desconectado")


app = NSApplication.sharedApplication()
app.setActivationPolicy_(NSApplicationActivationPolicyAccessory)

ctl = MenuController.alloc().init()
item = NSStatusBar.systemStatusBar().statusItemWithLength_(NSVariableStatusItemLength)
icon = NSImage.imageWithSystemSymbolName_accessibilityDescription_(
    "iphone.gen3.radiowaves.left.and.right", "Espejo Android")
if icon is not None:
    icon.setTemplate_(True)                    # se adapta a modo claro/oscuro
    item.button().setImage_(icon)
else:
    item.button().setTitle_("📱")

menu = NSMenu.alloc().init()
menu.setAutoenablesItems_(False)   # el enabled lo controla menuNeedsUpdate_
menu.setDelegate_(ctl)
ctl.status_item = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
    "…", None, "")
ctl.status_item.setEnabled_(False)
menu.addItem_(ctl.status_item)
menu.addItem_(NSMenuItem.separatorItem())
ctl.connect_item = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
    "Conectar espejo por WiFi", "connectWifi:", "")
ctl.connect_item.setTarget_(ctl)
menu.addItem_(ctl.connect_item)
ctl.disconnect_item = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
    "Desconectar espejo WiFi", "disconnectWifi:", "")
ctl.disconnect_item.setTarget_(ctl)
menu.addItem_(ctl.disconnect_item)
item.setMenu_(menu)

app.run()

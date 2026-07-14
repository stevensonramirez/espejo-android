#!/opt/homebrew/bin/python3.13
# -*- coding: utf-8 -*-
"""
Barra de botones para controlar el Android espejado con scrcpy — versión
NATIVA (AppKit/PyObjC). Reemplaza la versión Tk (respaldo en
android-buttons-tk.py.bak), que era lenta y frágil en macOS.

- Panel HUD translúcido con esquinas redondeadas (NSVisualEffectView).
- Íconos SF Symbols del sistema + tooltips nativos (instantáneos y bien puestos).
- Panel NO-ACTIVANTE: los clics no roban el foco -> botones livianos.
- Sigue a la ventana del espejo (mismo Space, multi-monitor, nunca la tapa)
  y comparte su nivel: flota solo cuando el espejo está al frente.
- La lanza el watcher scrcpy-autostart.sh (la revive si muere).
"""
import os
import subprocess
import threading
import time

ADB = "/opt/homebrew/bin/adb"
GAP = 6                 # separación entre el espejo y la barra

# El watcher escribe aquí el serial del teléfono conectado (barra genérica:
# funciona con cualquier Android autorizado, no hay serial quemado).
SERIAL_FILE = "/tmp/android-mirror-serial"
def _serial():
    try:
        with open(SERIAL_FILE) as f:
            return f.read().strip()
    except Exception:
        return ""

from Foundation import NSObject, NSProcessInfo

# Sin esto, macOS aplica "App Nap" a esta app accesoria y le retrasa los
# timers -> la barra seguía al espejo a saltos. Latencia crítica = ticks
# puntuales; AllowingIdleSystemSleep = no impide que el Mac duerma.
_NSActivityUserInitiatedAllowingIdleSystemSleep = 0x00FFFFFF & ~0x00100000
_NSActivityLatencyCritical = 0xFF00000000
_activity = NSProcessInfo.processInfo().beginActivityWithOptions_reason_(
    _NSActivityUserInitiatedAllowingIdleSystemSleep | _NSActivityLatencyCritical,
    "seguir la ventana del espejo sin lag")
from AppKit import (
    NSApplication, NSApplicationActivationPolicyAccessory,
    NSBackingStoreBuffered, NSBox, NSBoxSeparator, NSButton,
    NSButtonTypeMomentaryChange, NSColor,
    NSFloatingWindowLevel, NSImage, NSImageOnly, NSImageSymbolConfiguration,
    NSFontWeightMedium, NSMakeRect, NSNormalWindowLevel, NSPanel, NSScreen,
    NSTimer, NSVisualEffectBlendingModeBehindWindow, NSVisualEffectView,
    NSVisualEffectMaterialHUDWindow, NSVisualEffectStateActive,
    NSWindowCollectionBehaviorCanJoinAllSpaces,
    NSWindowCollectionBehaviorFullScreenAuxiliary,
    NSWindowStyleMaskBorderless, NSWindowStyleMaskNonactivatingPanel,
    NSWorkspace,
)
from Quartz import (CGWindowListCopyWindowInfo, kCGNullWindowID,
                    kCGWindowBounds, kCGWindowListOptionIncludingWindow,
                    kCGWindowListOptionOnScreenOnly, kCGWindowIsOnscreen,
                    kCGWindowNumber, kCGWindowOwnerName,
                    CGEventTapCreate, CGEventTapEnable, CGEventMaskBit,
                    kCGSessionEventTap, kCGHeadInsertEventTap,
                    kCGEventTapOptionListenOnly, kCGEventLeftMouseDragged,
                    kCGEventTapDisabledByTimeout, kCGEventTapDisabledByUserInput,
                    CFMachPortCreateRunLoopSource, CFRunLoopGetMain,
                    CFRunLoopAddSource, kCFRunLoopCommonModes)

# ---------------------------------------------------------------- adb helpers
def adb(*args):
    s = _serial()
    cmd = [ADB] + (["-s", s] if s else []) + list(args)
    return subprocess.run(cmd, capture_output=True)

# El watcher escribe aquí a qué display mandar los eventos:
# 0 = display real · >0 = display virtual (modo --new-display, hoy sin uso).
MODE_FILE = "/tmp/android-mirror-display"
def _target_display():
    try:
        with open(MODE_FILE) as f:
            return int(f.read().strip() or 0)
    except Exception:
        return 0

def keyevent(code):
    def run():
        d = _target_display()
        extra = ["-d", str(d)] if d else []
        adb("shell", "input", *extra, "keyevent", str(code))
    threading.Thread(target=run, daemon=True).start()

def shell_async(*args):
    threading.Thread(target=lambda: adb("shell", *args), daemon=True).start()

# ------------------------------------------------- System Events (Accesibilidad)
_warned = {"acc": False}
def osa(script):
    return subprocess.run(["osascript", "-e", script], capture_output=True, text=True)

def need_accessibility(err):
    if "-1719" in err or "not allowed assistive" in err:
        if not _warned["acc"]:
            _warned["acc"] = True
            subprocess.Popen(["osascript", "-e",
                'display dialog "Para Zoom y Pantalla completa, activa Accesibilidad para Python en Ajustes del Sistema > Privacidad y seguridad > Accesibilidad." '
                'buttons {"Abrir Ajustes", "Ahora no"} default button 1 with title "Permiso necesario"'
                ' \nif button returned of result is "Abrir Ajustes" then open location "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"'])
        return True
    return False

def raise_mirror():
    # Trae el espejo al frente (el auto-lanzamiento lo abre DETRÁS de todo, y
    # al pulsar un botón barra y espejo deben subir juntos).
    def run():
        osa('tell application "System Events" to set frontmost of process "scrcpy" to true')
    threading.Thread(target=run, daemon=True).start()

def scrcpy_zoom(factor):
    def run():
        r = osa('tell application "System Events" to tell process "scrcpy" to get size of window 1')
        if r.returncode != 0:
            need_accessibility(r.stderr); return
        try:
            w, h = [int(x) for x in r.stdout.strip().split(", ")]
        except Exception:
            return
        nw, nh = max(200, round(w * factor)), max(360, round(h * factor))
        osa(f'tell application "System Events" to tell process "scrcpy" to set size of window 1 to {{{nw}, {nh}}}')
    threading.Thread(target=run, daemon=True).start()

def scrcpy_fullscreen():
    def run():
        r = osa('tell application "System Events"\n'
                'set frontmost of process "scrcpy" to true\n'
                'keystroke "f" using {option down}\n'
                'end tell')
        if r.returncode != 0:
            need_accessibility(r.stderr)
    threading.Thread(target=run, daemon=True).start()

# ------------------------------------------------------------------- acciones
def _virtual_sf_display():
    # ID SurfaceFlinger del display virtual "scrcpy" (screencap en modo virtual).
    r = adb("shell", "dumpsys", "SurfaceFlinger", "--display-id")
    for line in r.stdout.decode(errors="replace").splitlines():
        if "Virtual display" in line and "scrcpy" in line:
            return line.split()[1]
    return None

def screenshot():
    def run():
        ts = time.strftime("%Y%m%d_%H%M%S")
        remote = f"/sdcard/DCIM/Screenshots/Screenshot_{ts}.png"
        local = f"/tmp/android_ss_{ts}.png"
        adb("shell", "mkdir", "-p", "/sdcard/DCIM/Screenshots")
        sf = _virtual_sf_display() if _target_display() else None
        extra = ["-d", sf] if sf else []
        adb("shell", "screencap", "-p", *extra, remote)
        adb("pull", remote, local)
        adb("shell", "am", "broadcast", "-a",
            "android.intent.action.MEDIA_SCANNER_SCAN_FILE", "-d", f"file://{remote}")
        osa(f'set the clipboard to (read (POSIX file "{local}") as «class PNGf»)')
        # confirmación: notificación de macOS + el botón cambia a ✓ un momento
        osa('display notification "Guardada en el teléfono y copiada al portapapeles" '
            'with title "Captura de Android" sound name "Glass"')
        try:
            ctl.performSelectorOnMainThread_withObject_waitUntilDone_("flashShot:", None, False)
        except Exception:
            pass
    threading.Thread(target=run, daemon=True).start()

_rot = {"land": False}
def rotate():
    # Rotación NATIVA: bloquea la orientación en horizontal y cada app decide —
    # las que admiten horizontal rotan de verdad (se expanden); las que no
    # (p. ej. el home) se quedan en vertical. Nada de forzar el display
    # (fixed-to-user-rotation dejaba las apps apeñuzcadas en modo compatibilidad).
    _rot["land"] = not _rot["land"]
    if _rot["land"]:
        shell_async("wm", "user-rotation", "lock", "1")
    else:
        shell_async("wm", "user-rotation", "free")
        shell_async("wm", "fixed-to-user-rotation", "default")  # auto-sanar restos

# --- modo tablet: redimensiona el display REAL del teléfono ------------------
# Nada de pantallas virtuales (el launcher secundario era inútil): se cambia
# el tamaño/densidad LÓGICOS del display real (wm size/density) -> el MISMO
# teléfono (tu launcher, tus apps, tus notificaciones) pero con lienzo y
# densidad de tablet (sw ~1066dp -> layout de tablet). La ventana del espejo
# se redimensiona sola. La pantalla física está apagada, así que no se nota;
# el estado se verifica en el teléfono (Override) para no perder sincronía si
# la barra renace. Blindaje: lidguard y el watcher lo resetean si algo se cae.
TABLET = {"on": False, "win": None}
TABLET_SIZE, TABLET_DENSITY = "2560x1600", "240"   # APAISADO (nace horizontal)
TABLET_WIN = (1150, 747)      # ventana macOS en modo tablet (contenido 16:10)
DEFAULT_WIN = (381, 959)      # ventana por defecto del espejo (si no hay guardada)

def _launcher_pkg():
    # launcher por defecto del teléfono (para reiniciarlo tras cambiar densidad)
    out = adb("shell", "cmd", "shortcut",
              "get-default-launcher").stdout.decode(errors="replace")
    try:
        return out.split("{")[1].split("/")[0]
    except Exception:
        return None

def _restart_launcher():
    # El launcher (p. ej. el de Moto) queda con el dock roto/imclicable al
    # cambiar wm size/density: reiniciarlo lo re-dibuja bien al instante.
    pkg = _launcher_pkg()
    if pkg:
        adb("shell", "am", "force-stop", pkg)
        adb("shell", "input", "keyevent", "3")      # HOME -> lo relanza

def _set_mirror_size(w, h):
    osa('tell application "System Events" to tell process "scrcpy" '
        f'to set size of window 1 to {{{w}, {h}}}')

def tablet_toggle():
    def run():
        if ":" in _serial():                        # sesión WiFi -> no
            osa('display notification "El modo tablet solo está disponible '
                'con cable USB (por WiFi se pone lento)." '
                'with title "Espejo Android"')
            return
        out = adb("shell", "wm", "size").stdout.decode(errors="replace")
        if "Override" in out:                       # APAGAR: volver al real
            adb("shell", "wm size reset; wm density reset")
            TABLET["on"] = False
            _restart_launcher()
            time.sleep(1.2)                         # scrcpy re-adapta el video
            w, h = TABLET.get("win") or DEFAULT_WIN
            _set_mirror_size(w, h)
        else:                                       # PRENDER: lienzo tablet
            r = osa('tell application "System Events" to tell process '
                    '"scrcpy" to get size of window 1')
            try:                                    # recordar tamaño actual
                TABLET["win"] = [int(x) for x in r.stdout.strip().split(", ")]
            except Exception:
                TABLET["win"] = None
            adb("shell", f"wm size {TABLET_SIZE}; wm density {TABLET_DENSITY}")
            TABLET["on"] = True
            _restart_launcher()
            time.sleep(1.2)
            _set_mirror_size(*TABLET_WIN)
        try:
            ctl.performSelectorOnMainThread_withObject_waitUntilDone_(
                "tintTablet:", None, False)
        except Exception:
            pass
    threading.Thread(target=run, daemon=True).start()

def _tint_tablet():
    if _tablet_btn is not None:
        _tablet_btn.setContentTintColor_(
            NSColor.systemBlueColor() if TABLET["on"] else NSColor.labelColor())

# (sf_symbol, glifo_fallback, tooltip, acción) — grupo de uso común
ITEMS = [
    ("plus.magnifyingglass",  "＋", "Agrandar ventana", lambda: scrcpy_zoom(1.12)),
    ("minus.magnifyingglass", "－", "Achicar ventana",  lambda: scrcpy_zoom(0.89)),
    ("camera.viewfinder", "◉", "Captura → teléfono + portapapeles", screenshot),
    ("bell", "▾", "Notificaciones", lambda: shell_async("cmd", "statusbar", "expand-notifications")),
    ("chevron.backward", "‹", "Atrás",     lambda: keyevent(4)),
    ("house",            "⌂", "Inicio",    lambda: keyevent(3)),
    ("square.on.square", "❐", "Recientes", lambda: keyevent(187)),
    ("line.3.horizontal","≡", "Menú",      lambda: keyevent(82)),
    ("speaker.wave.3",   "🔊", "Volumen +", lambda: keyevent(24)),
    ("speaker.wave.1",   "🔉", "Volumen −", lambda: keyevent(25)),
    ("rotate.right",     "⟳", "Rotar", rotate),
]
# separados abajo, tras una línea (uso menos frecuente / con más consecuencias)
BOTTOM = [
    ("arrow.up.left.and.arrow.down.right", "⛶", "Pantalla completa", scrcpy_fullscreen),
    ("ipad.landscape", "▭", "Modo tablet (más espacio, mismo teléfono)", tablet_toggle),
    ("power", "⏻", "Pantalla del teléfono on/off", lambda: keyevent(26)),
]
ACTIONS = ITEMS + BOTTOM

# --------------------------------------------------------- geometría / espejo
# Rastreo barato: se busca el ID de la ventana de scrcpy UNA vez (scan completo)
# y de ahí en adelante se consulta solo esa ventana (~0.2ms), lo que permite
# seguirla a 30fps mientras se mueve sin gastar CPU cuando está quieta.
_win = {"id": None}

def _find_mirror_id():
    info = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID) or []
    for w in info:
        if w.get(kCGWindowOwnerName) == "scrcpy":
            b = w.get(kCGWindowBounds)
            if b and int(b["Width"]) > 50 and int(b["Height"]) > 50:
                return w.get(kCGWindowNumber)
    return None

def _mirror_state():
    # ((x,y,w,h) en coords CG | None, visible_en_este_Space: bool)
    try:
        if _win["id"]:
            info = CGWindowListCopyWindowInfo(kCGWindowListOptionIncludingWindow,
                                              _win["id"]) or []
            for w in info:
                if w.get(kCGWindowOwnerName) == "scrcpy":
                    b = w.get(kCGWindowBounds)
                    if b and int(b["Width"]) > 50:
                        on = bool(w.get(kCGWindowIsOnscreen, False))
                        return (int(b["X"]), int(b["Y"]),
                                int(b["Width"]), int(b["Height"])), on
            _win["id"] = None          # la ventana murió (scrcpy renació)
        wid = _find_mirror_id()
        if wid:
            _win["id"] = wid
            return _mirror_state()
    except Exception:
        pass
    return None, False

def _screen_right_edge(x, w):
    # Borde derecho del MONITOR donde está el espejo (multi-pantalla).
    try:
        cx = x + w / 2
        for s in NSScreen.screens():
            f = s.frame()
            if f.origin.x <= cx < f.origin.x + f.size.width:
                return int(f.origin.x + f.size.width)
    except Exception:
        pass
    return None

def _reposition(b):
    # Pega la barra al costado del espejo (derecha; izquierda si no cabe).
    x, y, w, h = b
    nx = x + w + GAP
    limit = _screen_right_edge(x, w)
    if limit is not None and nx + PANEL_W > limit:
        nx = x - PANEL_W - GAP
    # CG (origen arriba) -> AppKit (origen abajo, pantalla principal)
    prim_h = NSScreen.screens()[0].frame().size.height
    STATE["prog_move"] = True
    panel.setFrameOrigin_((nx, prim_h - y - PANEL_H))
    STATE["prog_move"] = False
    STATE["moved_at"] = time.time()

def _scrcpy_is_front():
    try:
        fa = NSWorkspace.sharedWorkspace().frontmostApplication()
        return bool(fa) and (fa.localizedName() == "scrcpy"
                             or fa.processIdentifier() == os.getpid())
    except Exception:
        return False

# ------------------------------------------------------------------ interfaz
BTN_W, BTN_H, PAD, SP = 30, 24, 5, 2
FOLLOW = {"on": True}
STATE = {"raised": False, "prog_move": False, "last": None, "moved_at": 0.0}
# Nota: se intentó seguimiento por eventos (AXObserver) pero PyObjC no soporta
# ese callback ("Callable argument is not a PyObjC closure"). El poll
# adaptativo sobre la ventana exacta da el mismo resultado visual.

app = NSApplication.sharedApplication()
app.setActivationPolicy_(NSApplicationActivationPolicyAccessory)

# Primera ejecución en una máquina nueva: pedirle a macOS que muestre el
# diálogo de Accesibilidad para Python (zoom, fullscreen y seguimiento por
# eventos lo necesitan). Si ya está concedido, no pasa nada.
try:
    from ApplicationServices import AXIsProcessTrustedWithOptions
    AXIsProcessTrustedWithOptions({"AXTrustedCheckOptionPrompt": True})
except Exception:
    pass

SEP_H = 9                                # alto de la zona de la línea separadora
_n = 1 + len(ITEMS) + len(BOTTOM)        # pin + comunes + grupo de abajo
PANEL_W = BTN_W + PAD * 2
PANEL_H = _n * (BTN_H + SP) - SP + PAD * 2 + SEP_H

panel = NSPanel.alloc().initWithContentRect_styleMask_backing_defer_(
    NSMakeRect(200, 200, PANEL_W, PANEL_H),
    NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel,
    NSBackingStoreBuffered, False)
panel.setOpaque_(False)
panel.setBackgroundColor_(NSColor.clearColor())
panel.setHasShadow_(True)
panel.setHidesOnDeactivate_(False)
panel.setBecomesKeyOnlyIfNeeded_(True)
panel.setMovableByWindowBackground_(True)   # arrastrar por el fondo suelta el "seguir"
panel.setCollectionBehavior_(NSWindowCollectionBehaviorCanJoinAllSpaces
                             | NSWindowCollectionBehaviorFullScreenAuxiliary)
panel.setLevel_(NSNormalWindowLevel)

fx = NSVisualEffectView.alloc().initWithFrame_(NSMakeRect(0, 0, PANEL_W, PANEL_H))
fx.setMaterial_(NSVisualEffectMaterialHUDWindow)
fx.setBlendingMode_(NSVisualEffectBlendingModeBehindWindow)
fx.setState_(NSVisualEffectStateActive)
fx.setWantsLayer_(True)
fx.layer().setCornerRadius_(9.0)
fx.layer().setMasksToBounds_(True)
panel.setContentView_(fx)

_sym_cfg = NSImageSymbolConfiguration.configurationWithPointSize_weight_(12.0, NSFontWeightMedium)

def _make_button(y, symbol, fallback, tip, target, action, tag):
    b = NSButton.alloc().initWithFrame_(NSMakeRect(PAD, y, BTN_W, BTN_H))
    b.setBordered_(False)
    b.setButtonType_(NSButtonTypeMomentaryChange)
    img = NSImage.imageWithSystemSymbolName_accessibilityDescription_(symbol, tip) if symbol else None
    if img is not None:
        b.setImage_(img.imageWithSymbolConfiguration_(_sym_cfg))
        b.setImagePosition_(NSImageOnly)
        b.setContentTintColor_(NSColor.labelColor())
    else:
        b.setTitle_(fallback)
    b.setToolTip_(tip)
    b.setTarget_(target)
    b.setAction_(action)
    b.setTag_(tag)
    fx.addSubview_(b)
    return b

class Controller(NSObject):
    def buttonClicked_(self, sender):
        raise_mirror()                      # barra y espejo suben juntos
        ACTIONS[sender.tag()][3]()

    def pinClicked_(self, sender):
        FOLLOW["on"] = not FOLLOW["on"]
        self.tintPin()

    def tintPin(self):
        pin_btn.setContentTintColor_(
            NSColor.systemBlueColor() if FOLLOW["on"] else NSColor.tertiaryLabelColor())

    # --- confirmación visual de la captura: ✓ verde un momento ---
    def flashShot_(self, _):
        img = NSImage.imageWithSystemSymbolName_accessibilityDescription_(
            "checkmark.circle.fill", "listo")
        if img is not None and _shot_btn is not None:
            _shot_btn.setImage_(img.imageWithSymbolConfiguration_(_sym_cfg))
            _shot_btn.setContentTintColor_(NSColor.systemGreenColor())
            NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
                1.2, self, "restoreShot:", None, False)

    def restoreShot_(self, _):
        img = NSImage.imageWithSystemSymbolName_accessibilityDescription_(
            "camera.viewfinder", "captura")
        if img is not None and _shot_btn is not None:
            _shot_btn.setImage_(img.imageWithSymbolConfiguration_(_sym_cfg))
            _shot_btn.setContentTintColor_(NSColor.labelColor())

    def dragSync(self):
        # Llamado por el event tap en cada evento de arrastre del mouse:
        # si el espejo cambió de sitio, la barra lo sigue en ese mismo evento.
        if FOLLOW["on"]:
            b, on = _mirror_state()
            if b and on and b != STATE["last"]:
                _reposition(b)
                STATE["last"] = b

    def windowDidMove_(self, note):
        # Movimiento MANUAL (no programático) -> soltar el "seguir".
        if not STATE["prog_move"] and FOLLOW["on"]:
            FOLLOW["on"] = False
            self.tintPin()

    def tintTablet_(self, _):
        _tint_tablet()

    def poll_(self, timer):
        b, onscreen = _mirror_state()
        interval = 0.3                      # reposo sin espejo
        if b and onscreen:
            if not STATE["raised"]:         # primera vez que lo vemos -> al frente
                STATE["raised"] = True
                raise_mirror()
            if FOLLOW["on"] and b != STATE["last"]:
                _reposition(b)
            STATE["last"] = b
            if not panel.isVisible():
                panel.orderFrontRegardless()
            panel.setLevel_(NSFloatingWindowLevel if _scrcpy_is_front()
                            else NSNormalWindowLevel)
            # adaptativo: 60fps mientras el espejo se está moviendo, calma si no
            interval = 0.016 if time.time() - STATE["moved_at"] < 0.8 else 0.08
        elif panel.isVisible():             # el espejo no está en este Space
            panel.orderOut_(None)
            STATE["last"] = None
        NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
            interval, self, "poll:", None, False)

ctl = Controller.alloc().init()
panel.setDelegate_(ctl)

# --- seguimiento PEGADO al arrastre: event tap (solo escucha) de mouse-drag.
# En cada evento de arrastre se re-sincroniza la barra -> se mueve con el
# espejo como una sola pieza. (AXObserver no sirve: PyObjC no soporta ese
# callback; los monitores globales de NSEvent tampoco llegan a apps accesorias.)
def _drag_cb(proxy, etype, event, refcon):
    if etype in (kCGEventTapDisabledByTimeout, kCGEventTapDisabledByUserInput):
        CGEventTapEnable(_tap, True)        # macOS lo apaga si se demora: revivir
        return event
    try:
        ctl.dragSync()
    except Exception as e:
        print("drag-tap error:", e, flush=True)
    return event

_tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap,
                        kCGEventTapOptionListenOnly,
                        CGEventMaskBit(kCGEventLeftMouseDragged), _drag_cb, None)
if _tap:
    CFRunLoopAddSource(CFRunLoopGetMain(),
                       CFMachPortCreateRunLoopSource(None, _tap, 0),
                       kCFRunLoopCommonModes)
    CGEventTapEnable(_tap, True)
print(f"drag-tap: {'OK' if _tap else 'FALLO (sin permiso de Accesibilidad?)'}",
      flush=True)

_y = PANEL_H - PAD - BTN_H
pin_btn = _make_button(_y, "pin.fill", "📌", "Seguir el espejo (on/off)",
                       ctl, "pinClicked:", 900)
ctl.tintPin()
_shot_btn = None
_tablet_btn = None
for i, (sym, fb, tip, _fn) in enumerate(ITEMS):
    _y -= BTN_H + SP
    b = _make_button(_y, sym, fb, tip, ctl, "buttonClicked:", i)
    if sym == "camera.viewfinder":
        _shot_btn = b
# línea separadora antes del grupo de abajo
_y -= SEP_H
_sep = NSBox.alloc().initWithFrame_(NSMakeRect(PAD + 3, _y + SEP_H // 2, BTN_W - 6, 1))
_sep.setBoxType_(NSBoxSeparator)
fx.addSubview_(_sep)
for j, (sym, fb, tip, _fn) in enumerate(BOTTOM):
    _y -= BTN_H + SP
    b = _make_button(_y, sym, fb, tip, ctl, "buttonClicked:", len(ITEMS) + j)
    if sym == "ipad.landscape":
        _tablet_btn = b

# Poll adaptativo encadenado (one-shot): cada pasada agenda la siguiente con
# el intervalo que toque — 30fps mientras el espejo se mueve, reposo si no.
NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
    0.1, ctl, "poll:", None, False)

panel.orderFrontRegardless()
app.run()

"""Floating pill overlay — Qt/QML port of the macOS TranscriptionIndicatorView.

Uses PySide6 + QML for GPU-accelerated rendering with proper transparency,
smooth animations, and anti-aliased vector graphics.
"""
from __future__ import annotations

import os
import queue
import sys
import threading
import textwrap
from typing import Optional

from PySide6.QtCore import (
    QObject, Qt, QTimer, QUrl, Property, Signal, Slot,
)
from PySide6.QtGui import QGuiApplication, QColor
from PySide6.QtQml import QQmlApplicationEngine


# ── QML source ───────────────────────────────────────────────────────────────

_QML = textwrap.dedent(r"""
    import QtQuick
    import QtQuick.Window

    Window {
        id: root
        visible: true
        width: 80
        height: 30
        x: (Screen.width - width) / 2
        y: 16
        flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool | Qt.WindowTransparentForInput
        color: "transparent"

        // Bridge properties from Python
        property string appState: "idle"
        property real rainbowHue: 0
        property real cometAngle: 0
        property int ellipsisTick: 0

        onAppStateChanged: {
            if (appState === "idle") {
                fadeOut.start()
            } else if (appState === "recording") {
                // Instant appear — no fade delay on recording start
                root.visible = true
                orb.opacity = 1.0
            } else {
                root.visible = true
                fadeIn.start()
                if (appState === "processing") {
                    face.pickExpression()
                }
            }
        }

        // Fade animations
        NumberAnimation {
            id: fadeIn
            target: orb
            property: "opacity"
            from: orb.opacity
            to: 1.0
            duration: 180
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            id: fadeOut
            target: orb
            property: "opacity"
            from: orb.opacity
            to: 0.0
            duration: 200
            easing.type: Easing.InCubic
            onFinished: root.visible = false
        }

        Item {
            id: orb
            anchors.centerIn: parent
            width: appState === "recording" ? 56 : 16
            height: 16
            opacity: 0

            Behavior on width {
                NumberAnimation { duration: 150; easing.type: Easing.InOutQuad }
            }

            // ── Glow shadow ─────────────────────────────
            Rectangle {
                id: glow
                anchors.centerIn: parent
                width: parent.width + 12
                height: parent.height + 12
                radius: height / 2
                color: appState === "recording"
                    ? Qt.rgba(1, 0.23, 0.19, 0.35)
                    : appState === "processing"
                        ? Qt.hsla(rainbowHue, 1.0, 0.5, 0.2)
                        : "transparent"
                visible: appState !== "idle"

                // Blur approximation via layered rectangles
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 6
                    height: parent.height + 6
                    radius: height / 2
                    color: parent.color
                    opacity: 0.4
                }
            }

            // ── Pill body ───────────────────────────────
            Rectangle {
                id: pill
                anchors.fill: parent
                radius: height / 2
                color: appState === "recording" ? "#FF3B30"
                     : appState === "processing" ? "white"
                     : "#E8E8E8"

                // Inner shadow
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: height / 2
                    color: "transparent"
                    border.width: 2
                    border.color: appState === "recording"
                        ? Qt.rgba(0.7, 0, 0, 0.15)
                        : appState === "processing"
                            ? Qt.hsla(rainbowHue, 0.8, 0.5, 0.12)
                            : Qt.rgba(0, 0, 0, 0.05)
                }
            }

            // ── Rainbow comet border (processing) ───────
            Canvas {
                id: cometCanvas
                anchors.centerIn: parent
                width: parent.width + 6
                height: parent.height + 6
                visible: appState === "processing"

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)

                    var pw = orb.width + 6
                    var ph = orb.height + 6
                    var r = ph / 2
                    var straight = Math.max(0, pw - 2 * r)
                    var capLen = Math.PI * r
                    var total = 2 * straight + 2 * capLen
                    var n = 120

                    for (var i = 0; i < n; i++) {
                        var frac = i / n
                        var pointDeg = frac * 360
                        var delta = ((pointDeg - cometAngle) % 360 + 360) % 360

                        if (delta > 100) continue

                        var intensity = Math.pow(1.0 - delta / 100.0, 2.0)
                        var alpha = intensity * 0.9

                        if (alpha < 0.02) continue

                        var t = frac * total
                        var px, py

                        if (t < straight) {
                            px = r + t
                            py = 0
                        } else if (t < straight + capLen) {
                            var a = (t - straight) / capLen * Math.PI - Math.PI / 2
                            px = pw - r + r * Math.cos(a)
                            py = r + r * Math.sin(a)
                        } else if (t < 2 * straight + capLen) {
                            px = pw - r - (t - straight - capLen)
                            py = ph
                        } else {
                            var a2 = (t - 2 * straight - capLen) / capLen * Math.PI + Math.PI / 2
                            px = r + r * Math.cos(a2)
                            py = r + r * Math.sin(a2)
                        }

                        var hue = (rainbowHue + frac * 0.12) % 1.0
                        var dotR = 1.5 * (0.4 + 0.6 * intensity)

                        ctx.fillStyle = Qt.hsla(hue, 1.0, 0.5, alpha)
                        ctx.beginPath()
                        ctx.arc(px, py, dotR, 0, 2 * Math.PI)
                        ctx.fill()
                    }
                }
            }

            // Repaint comet when angle changes
            Connections {
                target: root
                function onCometAngleChanged() {
                    if (appState === "processing")
                        cometCanvas.requestPaint()
                }
            }

            // ── Face ────────────────────────────────────
            Item {
                id: face
                anchors.fill: parent

                property string expression: "surprise"
                property color faceColor: appState === "recording"
                    ? "white"
                    : appState === "processing"
                        ? Qt.hsla(rainbowHue, 0.85, 0.4, 0.85)
                        : "#555555"

                function pickExpression() {
                    var r = Math.random()
                    if (r < 0.05) expression = "skeptical"
                    else {
                        var opts = ["surprise", "smile", "thinking"]
                        expression = opts[Math.floor(Math.random() * 3)]
                    }
                }

                // Eyes
                Row {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -1
                    spacing: parent.width * 0.35 - 4

                    // Left eye
                    Rectangle {
                        width: face.expression === "skeptical" && appState === "processing" ? 4 : 2
                        height: face.expression === "skeptical" && appState === "processing" ? 0.8 : 2
                        radius: face.expression === "skeptical" && appState === "processing" ? 0 : 1
                        color: face.faceColor
                    }

                    // Right eye
                    Rectangle {
                        width: face.expression === "skeptical" && appState === "processing" ? 4 : 2
                        height: face.expression === "skeptical" && appState === "processing" ? 0.8 : 2
                        radius: face.expression === "skeptical" && appState === "processing" ? 0 : 1
                        color: face.faceColor
                    }
                }

                // Mouth
                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: 2.5

                    // :O mouth (recording + surprise)
                    Rectangle {
                        visible: appState === "recording" ||
                                 (appState === "processing" && face.expression === "surprise")
                        anchors.centerIn: parent
                        width: appState === "recording" ? 3.5 : 4
                        height: width
                        radius: width / 2
                        color: appState === "recording" ? face.faceColor : "transparent"
                        border.width: appState === "recording" ? 0 : 1
                        border.color: face.faceColor
                    }

                    // Smile mouth
                    Canvas {
                        visible: appState === "processing" && face.expression === "smile"
                        width: 8
                        height: 4
                        anchors.centerIn: parent
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.strokeStyle = face.faceColor
                            ctx.lineWidth = 1.2
                            ctx.lineCap = "round"
                            ctx.beginPath()
                            ctx.moveTo(1, 0.5)
                            ctx.quadraticCurveTo(4, 3.5, 7, 0.5)
                            ctx.stroke()
                        }
                        Connections {
                            target: root
                            function onRainbowHueChanged() {
                                if (face.expression === "smile")
                                    parent.children[1].requestPaint()
                            }
                        }
                    }

                    // Thinking dots
                    Row {
                        visible: appState === "processing" && face.expression === "thinking"
                        anchors.centerIn: parent
                        spacing: 1.5
                        Repeater {
                            model: 3
                            Rectangle {
                                required property int index
                                width: 1.5
                                height: 1.5
                                radius: 0.75
                                color: face.faceColor
                                opacity: index < ((ellipsisTick / 6) % 4) ? 1.0 : 0.25
                            }
                        }
                    }

                    // Skeptical mouth
                    Rectangle {
                        visible: appState === "processing" && face.expression === "skeptical"
                        anchors.centerIn: parent
                        width: 5
                        height: 1
                        radius: 0.5
                        color: face.faceColor
                    }
                }
            }
        }
    }
""")


# ── Python bridge ────────────────────────────────────────────────────────────

class OverlayOrb:
    """QML-based overlay matching the macOS TranscriptionIndicatorView.

    Thread-safe: set_state() may be called from any thread.
    run_mainloop() must be called from the main thread.
    """

    def __init__(self) -> None:
        self._queue: queue.Queue = queue.Queue()
        self._app: Optional[QGuiApplication] = None
        self._engine: Optional[QQmlApplicationEngine] = None
        self._root = None
        self._state = "idle"
        self._rainbow_hue = 0.0
        self._comet_angle = 0.0
        self._ellipsis_tick = 0

    def set_state(self, state: str) -> None:
        self._queue.put(("state", state))

    def quit(self) -> None:
        self._queue.put(("quit", None))

    def run_mainloop(self, stop_event: threading.Event) -> None:
        # Prevent Qt from treating this as a GUI app that shows in taskbar
        os.environ.setdefault("QT_QPA_PLATFORM", "windows:darkmode=0")

        self._app = QGuiApplication.instance()
        if self._app is None:
            self._app = QGuiApplication(sys.argv)

        self._engine = QQmlApplicationEngine()

        # Load QML from string
        import tempfile
        qml_file = os.path.join(tempfile.gettempdir(), "chirp_overlay.qml")
        with open(qml_file, "w", encoding="utf-8") as f:
            f.write(_QML)
        self._engine.load(QUrl.fromLocalFile(qml_file))

        if not self._engine.rootObjects():
            raise RuntimeError("Failed to load overlay QML")

        self._root = self._engine.rootObjects()[0]

        # Timer for queue polling + animations
        timer = QTimer()
        timer.setInterval(16)  # ~60fps

        def tick():
            # Check stop
            if stop_event.is_set():
                self._app.quit()
                return

            # Drain command queue
            try:
                while True:
                    cmd, arg = self._queue.get_nowait()
                    if cmd == "state":
                        self._state = arg
                        self._root.setProperty("appState", arg)
                    elif cmd == "quit":
                        self._app.quit()
                        return
            except queue.Empty:
                pass

            # Animate processing state
            if self._state == "processing":
                self._rainbow_hue = (self._rainbow_hue + 0.012) % 1.0
                self._comet_angle = (self._comet_angle + 2.5) % 360
                self._ellipsis_tick += 1
                self._root.setProperty("rainbowHue", self._rainbow_hue)
                self._root.setProperty("cometAngle", self._comet_angle)
                self._root.setProperty("ellipsisTick", self._ellipsis_tick)

        timer.timeout.connect(tick)
        timer.start()

        self._app.exec()

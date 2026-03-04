"""Floating pill overlay — VibeBuddy-style on-screen indicator."""
from __future__ import annotations

import colorsys
import queue
import threading
import tkinter as tk
from typing import Optional

from PIL import Image, ImageDraw, ImageTk


class OverlayOrb:
    """Pill-shaped face that floats at the top-center of the screen.

    Thread-safe: set_state() may be called from any thread.
    run_mainloop() must be called from the main thread.
    """

    # Display dimensions (rendered at 3x then scaled down for crispness)
    SCALE = 3
    W = 80
    H = 22

    def __init__(self) -> None:
        self._queue: queue.Queue = queue.Queue()
        self._state = "idle"
        self._rainbow_hue = 0
        self._animating = False
        self._root: Optional[tk.Tk] = None
        self._label: Optional[tk.Label] = None
        self._tk_image = None  # keep ref to prevent GC

    # ── Public API (thread-safe) ────────────────────────────────────────────

    def set_state(self, state: str) -> None:
        """Queue a state change: 'idle', 'recording', or 'processing'."""
        self._queue.put(("state", state))

    def quit(self) -> None:
        self._queue.put(("quit", None))

    def run_mainloop(self, stop_event: threading.Event) -> None:
        """Create the Tk window and block until stop_event is set."""
        self._root = tk.Tk()
        self._root.withdraw()  # start hidden

        # Transparent, always-on-top, no decorations
        transparent = "#FF00FF"
        self._root.overrideredirect(True)
        self._root.attributes("-topmost", True)
        self._root.attributes("-toolwindow", True)
        self._root.attributes("-transparentcolor", transparent)
        self._root.configure(bg=transparent)

        sw = self._root.winfo_screenwidth()
        x = (sw - self.W) // 2
        self._root.geometry(f"{self.W}x{self.H}+{x}+28")

        self._label = tk.Label(self._root, bg=transparent, bd=0)
        self._label.pack()

        # Poll the command queue and stop event
        def _tick() -> None:
            if stop_event.is_set():
                self._root.quit()
                return
            self._drain_queue()
            self._root.after(50, _tick)

        self._root.after(50, _tick)
        self._root.mainloop()

    # ── Internal ────────────────────────────────────────────────────────────

    def _drain_queue(self) -> None:
        try:
            while True:
                cmd, arg = self._queue.get_nowait()
                if cmd == "state":
                    self._apply_state(arg)
                elif cmd == "quit":
                    self._root.quit()
                    return
        except queue.Empty:
            pass

    def _apply_state(self, state: str) -> None:
        self._animating = False  # cancel any in-progress animation
        self._state = state
        if state == "idle":
            self._root.withdraw()
        elif state == "recording":
            self._root.deiconify()
            self._root.lift()
            self._animating = True
            self._animate_recording()
        elif state == "processing":
            self._rainbow_hue = 0
            self._root.deiconify()
            self._root.lift()
            self._animating = True
            self._animate_rainbow()

    def _render(self) -> None:
        s = self.SCALE
        w, h = self.W * s, self.H * s
        img = Image.new("RGBA", (w, h), (255, 0, 255, 0))
        draw = ImageDraw.Draw(img)
        cx, cy = w // 2, h // 2
        pad = 2 * s

        if self._state == "recording":
            fill = "#FF3B30"
            outline = "#FF6B60"
            eye_col = "white"
            mouth_col = "white"
        elif self._state == "processing":
            fill = "white"
            r, g, b = colorsys.hsv_to_rgb(self._rainbow_hue / 360, 0.85, 1.0)
            outline = f"#{int(r*255):02x}{int(g*255):02x}{int(b*255):02x}"
            eye_col = "#333333"
            mouth_col = "#333333"
        else:
            return

        # Pill body
        pw, ph = w - 2 * pad, h - 2 * pad
        px, py = pad, pad
        r = ph // 2
        draw.ellipse([px, py, px + ph, py + ph], fill=fill)
        draw.ellipse([px + pw - ph, py, px + pw, py + ph], fill=fill)
        draw.rectangle([px + r, py, px + pw - r, py + ph], fill=fill)
        if outline:
            ow = max(1, s)
            draw.arc([px, py, px + ph, py + ph], 90, 270, fill=outline, width=ow)
            draw.arc([px + pw - ph, py, px + pw, py + ph], 270, 90, fill=outline, width=ow)
            draw.line([px + r, py, px + pw - r, py], fill=outline, width=ow)
            draw.line([px + r, py + ph, px + pw - r, py + ph], fill=outline, width=ow)

        # Eyes
        spread = int(pw * 0.20)
        eye_r = int(ph * 0.17)
        draw.ellipse([cx - spread - eye_r, cy - eye_r, cx - spread + eye_r, cy + eye_r], fill=eye_col)
        draw.ellipse([cx + spread - eye_r, cy - eye_r, cx + spread + eye_r, cy + eye_r], fill=eye_col)

        # Mouth
        if self._state == "recording":
            mr = int(ph * 0.14)
            draw.ellipse([cx - mr, cy - mr, cx + mr, cy + mr], fill=mouth_col)
        elif self._state == "processing":
            dot_r = max(1, int(ph * 0.09))
            gap = int(ph * 0.27)
            for dx in (-gap, 0, gap):
                draw.ellipse([cx + dx - dot_r, cy - dot_r, cx + dx + dot_r, cy + dot_r], fill=mouth_col)

        img = img.resize((self.W, self.H), Image.LANCZOS)
        self._tk_image = ImageTk.PhotoImage(img)
        self._label.configure(image=self._tk_image)

    def _animate_recording(self) -> None:
        if not self._animating or self._state != "recording":
            return
        self._render()
        self._root.after(120, self._animate_recording)

    def _animate_rainbow(self) -> None:
        if not self._animating or self._state != "processing":
            return
        self._rainbow_hue = (self._rainbow_hue + 8) % 360
        self._render()
        self._root.after(50, self._animate_rainbow)

"""System tray icon for Chirp — pill + face style ported from VibeBuddy."""
from __future__ import annotations

import threading
from typing import Callable, Optional

from PIL import Image, ImageDraw
import pystray


def _draw_pill(draw: ImageDraw.ImageDraw, x: int, y: int, w: int, h: int, fill, outline=None, outline_width: int = 0) -> None:
    r = h // 2
    draw.ellipse([x, y, x + h, y + h], fill=fill)
    draw.ellipse([x + w - h, y, x + w, y + h], fill=fill)
    draw.rectangle([x + r, y, x + w - r, y + h], fill=fill)
    if outline and outline_width:
        draw.line([x + r, y, x + w - r, y], fill=outline, width=outline_width)
        draw.line([x + r, y + h, x + w - r, y + h], fill=outline, width=outline_width)
        draw.arc([x, y, x + h, y + h], start=90, end=270, fill=outline, width=outline_width)
        draw.arc([x + w - h, y, x + w, y + h], start=270, end=90, fill=outline, width=outline_width)


def _make_icon(recording: bool, processing: bool = False) -> Image.Image:
    # Render at 3x for crispness, then scale down
    scale = 3
    size = 64
    rs = size * scale  # 192

    img = Image.new("RGBA", (rs, rs), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    cx, cy = rs // 2, rs // 2

    # Pill background (landscape, centred in the square canvas)
    pw = int(rs * 0.80)
    ph = int(rs * 0.36)
    px = (rs - pw) // 2
    py = (rs - ph) // 2

    if recording:
        fill = (255, 59, 48, 255)        # iOS red
        outline = (255, 107, 96, 255)
        eye_color = (255, 255, 255, 255)
        mouth_color = (255, 255, 255, 255)
    elif processing:
        fill = (255, 255, 255, 255)
        outline = (120, 200, 255, 255)
        eye_color = (51, 51, 51, 255)
        mouth_color = (51, 51, 51, 255)
    else:
        fill = (72, 72, 74, 255)         # dark gray
        outline = (99, 99, 102, 255)
        eye_color = (200, 200, 200, 255)
        mouth_color = (200, 200, 200, 255)

    _draw_pill(draw, px, py, pw, ph, fill=fill, outline=outline, outline_width=scale)

    # Eyes — two dots on either side of centre
    spread = int(pw * 0.22)
    eye_r = int(ph * 0.18)
    ey = cy
    draw.ellipse([cx - spread - eye_r, ey - eye_r, cx - spread + eye_r, ey + eye_r], fill=eye_color)
    draw.ellipse([cx + spread - eye_r, ey - eye_r, cx + spread + eye_r, ey + eye_r], fill=eye_color)

    # Mouth
    if recording:
        # Surprised "o"
        mr = int(ph * 0.15)
        draw.ellipse([cx - mr, ey - mr, cx + mr, ey + mr], fill=mouth_color)
    elif processing:
        # Three dots "..."
        dot_r = int(ph * 0.09)
        gap = int(ph * 0.28)
        for dx in (-gap, 0, gap):
            draw.ellipse([cx + dx - dot_r, ey - dot_r, cx + dx + dot_r, ey + dot_r], fill=mouth_color)
    # idle: no mouth — just eyes

    img = img.resize((size, size), Image.LANCZOS)
    return img


class TrayIcon:
    def __init__(self, *, on_quit: Callable[[], None]) -> None:
        self._on_quit = on_quit
        self._icon: Optional[pystray.Icon] = None
        self._recording = False
        self._processing = False

    def _build_menu(self) -> pystray.Menu:
        if self._recording:
            status = "● Recording"
        elif self._processing:
            status = "⋯ Processing"
        else:
            status = "○ Idle"
        return pystray.Menu(
            pystray.MenuItem(f"Chirp  —  {status}", None, enabled=False),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("Quit", self._quit),
        )

    def _quit(self, icon: pystray.Icon, item) -> None:
        icon.stop()
        self._on_quit()

    def _refresh(self) -> None:
        if self._icon:
            self._icon.icon = _make_icon(self._recording, self._processing)
            self._icon.menu = self._build_menu()
            if self._recording:
                self._icon.title = "Chirp — Recording…"
            elif self._processing:
                self._icon.title = "Chirp — Processing…"
            else:
                self._icon.title = "Chirp — Idle"

    def set_recording(self, recording: bool) -> None:
        self._recording = recording
        self._processing = False
        self._refresh()

    def set_processing(self, processing: bool) -> None:
        self._processing = processing
        self._recording = False
        self._refresh()

    def run_detached(self) -> None:
        self._icon = pystray.Icon(
            "Chirp",
            _make_icon(False),
            "Chirp — Idle",
            menu=self._build_menu(),
        )
        t = threading.Thread(target=self._icon.run, daemon=True)
        t.start()

    def stop(self) -> None:
        if self._icon:
            self._icon.stop()

from __future__ import annotations

import logging
import threading
from typing import Callable

import keyboard


class KeyboardShortcutManager:
    def __init__(self, *, logger: logging.Logger) -> None:
        self._logger = logger

    def register_push_to_talk(
        self,
        key: str,
        on_press: Callable[[], None],
        on_release: Callable[[], None],
    ) -> None:
        """Hold to record, release to stop.

        Uses separate on_press_key/on_release_key with suppress=True.
        Callbacks do MINIMAL work (append to queue) to avoid blocking
        the Windows low-level keyboard hook. A dispatcher thread runs
        the actual handlers.
        """
        event_queue: list[str] = []
        event_lock = threading.Lock()
        event_signal = threading.Event()

        def _on_press(event: keyboard.KeyboardEvent) -> None:
            with event_lock:
                event_queue.append("press")
            event_signal.set()

        def _on_release(event: keyboard.KeyboardEvent) -> None:
            with event_lock:
                event_queue.append("release")
            event_signal.set()

        def _dispatcher() -> None:
            """Separate thread that processes events off the hook thread."""
            held = False
            while True:
                event_signal.wait()
                event_signal.clear()
                with event_lock:
                    events = event_queue[:]
                    event_queue.clear()
                for ev in events:
                    if ev == "press":
                        if not held:
                            held = True
                            on_press()
                    else:
                        if held:
                            held = False
                            on_release()

        threading.Thread(target=_dispatcher, daemon=True, name="KeyDispatcher").start()
        keyboard.on_press_key(key, _on_press, suppress=True)
        keyboard.on_release_key(key, _on_release, suppress=True)
        self._logger.debug("Registered push-to-talk key (suppress): %s", key)

    def send(self, combination: str) -> None:
        keyboard.send(combination)

    def write(self, text: str) -> None:
        keyboard.write(text)

    def cleanup(self) -> None:
        """Remove all keyboard hooks so the process can exit cleanly."""
        keyboard.unhook_all()

    def wait(self) -> None:
        keyboard.wait()

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

        The key is suppressed so it never reaches the OS (no backtick typed,
        no modifier-stuck issues). on_press fires on the first KEY_DOWN (key
        repeat events are ignored). on_release fires on KEY_UP.
        """
        _held = False

        def _on_event(event: keyboard.KeyboardEvent) -> None:
            nonlocal _held
            if event.event_type == keyboard.KEY_DOWN:
                if not _held:
                    _held = True
                    threading.Thread(target=on_press, daemon=True).start()
            elif event.event_type == keyboard.KEY_UP:
                if _held:
                    _held = False
                    threading.Thread(target=on_release, daemon=True).start()

        keyboard.hook_key(key, _on_event, suppress=True)
        self._logger.debug("Registered push-to-talk key (hook_key, suppress): %s", key)

    def send(self, combination: str) -> None:
        keyboard.send(combination)

    def write(self, text: str) -> None:
        keyboard.write(text)

    def wait(self) -> None:
        keyboard.wait()

from __future__ import annotations

import threading
from typing import Callable, Optional

import numpy as np
import sounddevice as sd


class AudioCapture:
    def __init__(
        self,
        *,
        sample_rate: int = 16_000,
        channels: int = 1,
        dtype: str = "float32",
        status_callback: Optional[Callable[[str], None]] = None,
    ) -> None:
        self.sample_rate = sample_rate
        self.channels = channels
        self.dtype = dtype
        self._status_callback = status_callback
        self._stream: Optional[sd.InputStream] = None
        self._frames: list[np.ndarray] = []
        self._lock = threading.Lock()

    def start(self) -> None:
        if self._stream is not None:
            return

        def _callback(indata: np.ndarray, _frames: int, _time, status) -> None:  # type: ignore[name-defined]
            if status and self._status_callback:
                self._status_callback(str(status))
            with self._lock:
                self._frames.append(indata.copy())

        self._frames.clear()
        self._stream = sd.InputStream(
            samplerate=self.sample_rate,
            channels=self.channels,
            dtype=self.dtype,
            callback=_callback,
        )
        self._stream.start()

    def stop(self) -> np.ndarray:
        if self._stream is None:
            return np.empty(0, dtype=self.dtype)
        self._stream.stop()
        self._stream.close()
        self._stream = None
        with self._lock:
            if not self._frames:
                return np.empty(0, dtype=self.dtype)
            audio = np.concatenate(self._frames, axis=0)
            self._frames.clear()
        if self.channels == 1:
            audio = audio.reshape(-1)
        return audio.astype(np.float32, copy=False)


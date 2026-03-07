from __future__ import annotations

import gc
import logging
import threading
import time
from pathlib import Path
from typing import Optional, Sequence

import numpy as np
import onnx_asr
from onnx_asr.loader import ModelFileNotFoundError, ModelPathNotDirectoryError

try:
    import onnxruntime as ort
except ImportError:  # pragma: no cover - optional dependency
    ort = None  # type: ignore[assignment]


CPU_PROVIDERS: Sequence[str] = ("CPUExecutionProvider",)


class ModelNotPreparedError(RuntimeError):
    pass


class ParakeetManager:
    def __init__(
        self,
        *,
        model_name: str,
        quantization: Optional[str],
        provider_key: str,
        threads: Optional[int],
        logger: logging.Logger,
        model_dir: Path,
        timeout: float = 300.0,
    ) -> None:
        self._logger = logger
        self._model_name = model_name
        self._quantization = quantization
        self._providers = self._resolve_providers(provider_key)
        self._session_options = self._build_session_options(threads)
        self._model_dir = model_dir
        self._timeout = timeout  # 0 or negative means never unload
        self._last_access = time.time()
        self._lock = threading.Lock()
        self._model = self._load_model()
        self._stop_monitor = threading.Event()
        self._monitor_thread: Optional[threading.Thread] = None
        if self._timeout > 0:
            self._monitor_thread = threading.Thread(target=self._monitor_loop, daemon=True)
            self._monitor_thread.start()

    def _monitor_loop(self) -> None:
        while not self._stop_monitor.is_set():
            time.sleep(5)
            with self._lock:
                should_unload = (
                    self._model is not None
                    and self._timeout > 0
                    and (time.time() - self._last_access > self._timeout)
                )
            if should_unload:
                self._unload_model()

    def _unload_model(self) -> None:
        with self._lock:
            if self._model is not None and (time.time() - self._last_access > self._timeout):
                idle_secs = time.time() - self._last_access
                self._logger.info("Unloading Parakeet model after %.0fs idle (timeout=%.0fs)", idle_secs, self._timeout)
                self._model = None
                gc.collect()

    def ensure_loaded(self):
        with self._lock:
            if self._model is None:
                self._logger.info("Reloading Parakeet model (cold start)...")
                t0 = time.perf_counter()
                self._model = self._load_model()
                elapsed = time.perf_counter() - t0
                self._logger.info("Cold-start reload completed in %.2fs", elapsed)
            return self._model

    def _resolve_providers(self, key: str) -> Sequence[str]:
        normalized = key.lower()
        if normalized != "cpu":
            self._logger.warning(
                "GPU providers are not supported; forcing CPU provider (received: %s)",
                key,
            )
        return CPU_PROVIDERS

    def _build_session_options(self, threads: Optional[int]):
        if ort is None:
            if threads and threads > 0:
                self._logger.warning("onnxruntime not available; ignoring threads=%s", threads)
            return None

        options = ort.SessionOptions()
        # Optimization: Force inter_op_num_threads to 1.
        # This minimizes overhead for sequential models like Parakeet.
        options.inter_op_num_threads = 1

        if threads and threads > 0:
            options.intra_op_num_threads = threads
        return options

    def _load_model(self):
        self._logger.info(
            "Loading Parakeet model %s (quantization=%s, providers=%s)",
            self._model_name,
            self._quantization or "none",
            ",".join(self._providers),
        )
        self._model_dir.mkdir(parents=True, exist_ok=True)
        t0 = time.perf_counter()
        try:
            model = onnx_asr.load_model(
                self._model_name,
                path=str(self._model_dir),
                quantization=self._quantization,
                providers=self._providers,
                sess_options=self._session_options,
            )
        except (ModelPathNotDirectoryError, ModelFileNotFoundError) as exc:
            raise ModelNotPreparedError(
                f"Model not found at {self._model_dir} — run: uv run chirp-setup"
            ) from exc
        elapsed = time.perf_counter() - t0
        self._logger.info("Model loaded in %.2fs", elapsed)
        return model

    def warm_up(self) -> None:
        """Ensure model is loaded and run a tiny inference to warm up ONNX caches.

        Call this at recording-start so the model is hot by recording-stop.
        """
        t0 = time.perf_counter()
        model = self.ensure_loaded()
        load_elapsed = time.perf_counter() - t0
        # Run a minimal inference to warm up ONNX session internals
        t1 = time.perf_counter()
        try:
            dummy = np.zeros(1600, dtype=np.float32)  # 0.1s of silence
            model.recognize(dummy, sample_rate=16_000)
        except Exception:
            pass  # warmup failure is non-fatal
        warmup_elapsed = time.perf_counter() - t1
        self._logger.info("Model warm-up: load=%.3fs, dummy_infer=%.3fs, total=%.3fs",
                          load_elapsed, warmup_elapsed, time.perf_counter() - t0)

    def transcribe(self, audio: np.ndarray, *, sample_rate: int = 16_000, language: Optional[str] = None) -> str:
        t_total = time.perf_counter()
        with self._lock:
            self._last_access = time.time()
        t0 = time.perf_counter()
        model = self.ensure_loaded()
        self._logger.info("ensure_loaded took %.3fs", time.perf_counter() - t0)
        if audio.ndim > 1:
            audio = audio.reshape(-1)
        waveform = audio.astype(np.float32, copy=False)
        if waveform.size == 0:
            return ""
        audio_duration = waveform.size / sample_rate
        self._logger.info("Transcribing %.2fs of audio (%d samples)", audio_duration, waveform.size)
        t0 = time.perf_counter()
        result = model.recognize(waveform, sample_rate=sample_rate, language=language)
        recognize_elapsed = time.perf_counter() - t0
        total_elapsed = time.perf_counter() - t_total
        self._logger.info(
            "model.recognize took %.3fs (total transcribe: %.3fs, RTF: %.2fx)",
            recognize_elapsed, total_elapsed, recognize_elapsed / audio_duration if audio_duration > 0 else 0,
        )
        return result if isinstance(result, str) else str(result)

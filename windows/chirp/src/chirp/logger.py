from __future__ import annotations

import logging
import sys
from pathlib import Path

# Resolve log path once so other modules can find it.
if getattr(sys, "frozen", False):
    LOG_PATH = Path(sys.executable).parent / "chirp.log"
else:
    LOG_PATH = Path(__file__).resolve().parents[3] / "chirp.log"


def _is_frozen_windowless() -> bool:
    """True when running as a PyInstaller bundle with no console window."""
    return getattr(sys, "frozen", False) and not sys.stdout


def _make_handlers(level: int) -> list[logging.Handler]:
    handlers: list[logging.Handler] = []

    # Always write to a log file
    file_handler = logging.FileHandler(LOG_PATH, encoding="utf-8")
    file_handler.setFormatter(logging.Formatter(
        "%(asctime)s  %(levelname)-8s  %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    ))
    file_handler.setLevel(level)
    handlers.append(file_handler)

    # Also log to console when available
    if not _is_frozen_windowless():
        try:
            from rich.console import Console
            from rich.logging import RichHandler
            console_handler = RichHandler(
                console=Console(force_terminal=True), show_time=True, markup=False,
            )
            console_handler.setFormatter(logging.Formatter("%(message)s"))
            console_handler.setLevel(level)
            handlers.append(console_handler)
        except Exception:
            pass

    return handlers


def get_logger(name: str = "chirp", *, level: int = logging.INFO) -> logging.Logger:
    logger = logging.getLogger(name)
    if logger.handlers:
        logger.setLevel(level)
        for h in logger.handlers:
            h.setLevel(level)
        return logger
    logger.setLevel(level)
    for h in _make_handlers(level):
        logger.addHandler(h)
    logger.propagate = False
    return logger


def configure_root(level: int = logging.INFO) -> None:
    logging.basicConfig(level=level, handlers=_make_handlers(level))

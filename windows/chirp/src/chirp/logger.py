from __future__ import annotations

import logging
import sys
from pathlib import Path


def _is_frozen_windowless() -> bool:
    """True when running as a PyInstaller bundle with no console window."""
    return getattr(sys, "frozen", False) and not sys.stdout


def _make_handler(level: int) -> logging.Handler:
    if _is_frozen_windowless():
        # No console — log to a file next to the exe
        log_path = Path(sys.executable).parent / "chirp.log"
        handler = logging.FileHandler(log_path, encoding="utf-8")
        handler.setFormatter(logging.Formatter(
            "%(asctime)s  %(levelname)-8s  %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S",
        ))
    else:
        from rich.console import Console
        from rich.logging import RichHandler
        handler = RichHandler(console=Console(force_terminal=True), show_time=True, markup=False)
        handler.setFormatter(logging.Formatter("%(message)s"))
    handler.setLevel(level)
    return handler


def get_logger(name: str = "chirp", *, level: int = logging.INFO) -> logging.Logger:
    logger = logging.getLogger(name)
    if logger.handlers:
        logger.setLevel(level)
        for h in logger.handlers:
            h.setLevel(level)
        return logger
    logger.setLevel(level)
    logger.addHandler(_make_handler(level))
    logger.propagate = False
    return logger


def configure_root(level: int = logging.INFO) -> None:
    logging.basicConfig(level=level, handlers=[_make_handler(level)])

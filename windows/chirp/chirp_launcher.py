"""PyInstaller entry point for Chirp."""
import sys
import traceback
from pathlib import Path


def _write_crash_log(exc: BaseException) -> None:
    """Last-resort crash logger when the app logger isn't yet initialised."""
    try:
        log_path = Path(sys.executable).parent / "chirp.log"
        with log_path.open("a", encoding="utf-8") as fh:
            fh.write("\n=== UNHANDLED CRASH ===\n")
            traceback.print_exc(file=fh)
            fh.write("=======================\n")
    except Exception:
        pass  # Nothing left to do


if __name__ == "__main__":
    try:
        from chirp.main import main
        main()
    except SystemExit:
        raise  # Normal exit — don't log
    except BaseException as exc:  # noqa: BLE001
        _write_crash_log(exc)
        raise

# VibeBuddy for Windows

Windows port of VibeBuddy - push-to-talk voice dictation with visual feedback.

## Features

- Push-to-talk voice dictation (hold Alt to record)
- VibeBuddy-style capsule overlay with expressive face
- Red capsule during recording, rainbow border during processing
- Uses Whisper for fast local transcription (GPU accelerated)
- System tray icon with settings

## Requirements

- Python 3.11+
- NVIDIA GPU (recommended) or CPU fallback
- Windows 10/11

## Installation

```bash
pip install sounddevice numpy scipy pyperclip pyautogui pillow pystray faster-whisper pygame
```

## Usage

```bash
python dictate.py
```

Or build standalone exe:

```bash
pip install pyinstaller
pyinstaller --noconsole --onefile --name WinVoice --add-data "sounds;sounds" dictate.py
```

## Controls

- **Hold Alt**: Start recording (red capsule appears)
- **Release Alt**: Stop recording, transcribe, and paste
- **System tray icon**: Click for settings, right-click for menu

## Settings

Click the tray icon to configure:
- Hotkey (Alt, Ctrl, Shift, F1-F8)
- Whisper model size (tiny, base, small, medium, large-v3)
- Microphone selection
- Language

## Sound Effects

Uses the same sounds as macOS VibeBuddy:
- `startRecording.mp3` - Recording started
- `stopRecording.mp3` - Recording stopped
- `pasteTranscript.mp3` - Text pasted successfully

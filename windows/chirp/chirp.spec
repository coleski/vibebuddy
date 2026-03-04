# -*- mode: python ; coding: utf-8 -*-

a = Analysis(
    ['chirp_launcher.py'],
    pathex=['src'],
    binaries=[],
    datas=[
        ('src/chirp/assets/ping-up.wav',   'chirp/assets'),
        ('src/chirp/assets/ping-down.wav', 'chirp/assets'),
        ('.venv/Lib/site-packages/onnx_asr/preprocessors/*.onnx', 'onnx_asr/preprocessors'),
    ],
    hiddenimports=[
        'chirp',
        'chirp.main',
        'chirp.config_manager',
        'chirp.parakeet_manager',
        'chirp.audio_capture',
        'chirp.audio_feedback',
        'chirp.audio_feedback',
        'chirp.keyboard_shortcuts',
        'chirp.text_injector',
        'chirp.tray_icon',
        'chirp.overlay',
        'chirp.logger',
        'chirp.setup',
        'onnxruntime',
        'onnx_asr',
        'sounddevice',
        'pyperclip',
        'pystray',
        'PIL',
        'PIL.Image',
        'PIL.ImageDraw',
        'keyboard',
        'winsound',
        'numpy',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='chirp',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,        # No console window
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    uac_admin=False,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='chirp',
)

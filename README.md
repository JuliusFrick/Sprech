# Sprech

A minimal Mac dictation app that transcribes speech, removes filler words, and translates — all on-device.

## Features

- 🎤 **System-wide dictation** – Activate with a global hotkey
- 📝 **Filler word removal** – Automatically cleans up "äh", "öhm", etc.
- 🌐 **On-device translation** – Powered by Apple Translate
- 🔒 **Privacy first** – Everything runs locally on your Mac

## Requirements

- macOS 14.0+ (Sonoma or later)
- Apple Silicon (M1/M2/M3) for optimal MLX performance
- XcodeGen (install via Homebrew: `brew install xcodegen`)

## Setup

```bash
cd Sprech
chmod +x setup.sh
./setup.sh
```

## Building

After running setup, open `Sprech.xcodeproj` in Xcode and build.

## License

MIT

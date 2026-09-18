# VoiceFlow

VoiceFlow is a private, local macOS dictation app built with Swift, Parakeet, and Apple Speech.

## Requirements

- macOS 14 or later
- Apple Silicon or Intel Mac
- Xcode 16 or later

## Build

```sh
swift build -c release
swift test -c release
```

Grant Microphone and Accessibility permissions in VoiceFlow Settings before using global dictation and text insertion.

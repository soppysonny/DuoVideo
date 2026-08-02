# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Build & Run

This is an Xcode project — there is no CLI build command. Use Xcode directly:

- **Build**: `⌘B` in Xcode
- **Run on device**: `⌘R` (must use a physical device — simulator does not support `AVCaptureMultiCamSession`)
- **Minimum deployment target**: iOS 13.0
- **Bundle ID**: `com.mbjztech.doublerecorder`

There are no unit tests, linter config, or package dependencies in this project.

## Architecture

`ViewController` is the single screen. It owns all business objects and wires them together via `CameraManagerDelegate`.

**Data flow** (capture → write):
```
AVCaptureMultiCamSession (CameraManager)
  ├── back camera  → AVCaptureVideoDataOutput → delegate callback
  ├── front camera → AVCaptureVideoDataOutput → delegate callback
  └── microphone   → AVCaptureAudioDataOutput → delegate callback
          ↓
    VideoRecorder (serial writeQueue)
      ├── caches latest front CVPixelBuffer
      ├── on each back frame: PiPCompositor.composite(back, front) → compositePixelBuffer
      └── appends to 3 parallel AVAssetWriters:
            composite.mp4 (H.264 1920×1080, PiP overlay)
            back.mp4      (HEVC 1280×720, raw back camera)
            front.mp4     (HEVC 1280×720, raw front camera)
```

**Key constraint**: `VideoRecorder.writeQueue` is a serial queue. All three writers are driven from it. Audio `CMSampleBuffer`s must be shallow-copied via `CMSampleBufferCreateCopy` before appending to the second and third writers — the same buffer cannot be appended to multiple writers.

## Module Responsibilities

| File | Role |
|------|------|
| `Camera/CameraManager.swift` | Owns `AVCaptureMultiCamSession`. Uses `addInputWithNoConnections` / `addOutputWithNoConnections` / `addConnection` (required for MultiCam). Exposes `backPreviewLayer` and `frontPreviewLayer`. |
| `Metal/PiPCompositor.swift` + `.metal` | GPU compositing via `CVMetalTextureCache` (zero-copy). Swift `PiPParams` struct must be **24 bytes** to match Metal's `float2` alignment padding — it has a `_pad: Float` field for this. |
| `Recording/VideoRecorder.swift` | Coordinates 3× `AVAssetWriter`. Session starts on the first back-camera frame (`startSession(atSourceTime:)`). All three writers share the same `sessionStartTime`. |
| `Permissions/PermissionManager.swift` | Requests camera → mic → photo library in sequence. Photo library uses `authorizationStatus(for: .addOnly)` on iOS 14+, falls back to the parameterless API on iOS 13. |
| `ViewController.swift` | Checks `AVCaptureMultiCamSession.isMultiCamSupported` before requesting permissions. If unsupported, shows a blocking overlay. |

## Metal Struct Alignment

The `PiPParams` struct is shared between Swift and the Metal shader. Metal's `float2` forces 8-byte struct alignment, making the total size **24 bytes** (not 20). The Swift struct includes `var _pad: Float = 0` as the last field to match this. If you add fields to `PiPParams`, verify both sides stay in sync using `MemoryLayout<PiPParams>.size`.

## AVCaptureMultiCamSession Wiring

MultiCam requires explicit connection management — do **not** use `session.addInput()` / `session.addOutput()`. The correct pattern is:
1. `session.addInputWithNoConnections(input)`
2. `session.addOutputWithNoConnections(output)`
3. Get the specific `AVCaptureInputPort` for the target device position
4. `AVCaptureConnection(inputPorts: [port], output: output)` then `session.addConnection(connection)`

When setting `isVideoMirrored` on any connection, always set `automaticallyAdjustsVideoMirroring = false` first, otherwise AVFoundation throws `NSInvalidArgumentException`.

## Output Files

Recordings are written to `Documents/Recordings/` in the app sandbox, named `composite_YYYYMMDD_HHmmss.mp4`, `back_…`, `front_…`. They are deleted after successful export to Photos.

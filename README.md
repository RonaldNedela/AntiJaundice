# AntiJaundice

**Optical Edge Yellowing Compensation Filter for iPad Displays**  
*Targeted chromatic neutralization for degraded LOCA adhesive and polarizer aging on iPad Pro 10.5" (2017), iPad Pro 9.7", iPad Air 3, and laminated iOS panels.*

![iOS 12.0 - 18+](https://img.shields.io/badge/iOS-12.0--18%2B-blue?style=flat-square)
![Architecture](https://img.shields.io/badge/Architecture-arm64%20%7C%20arm64e-success?style=flat-square)
![Jailbreak](https://img.shields.io/badge/Jailbreak-Rootless%20%26%20Rootful-orange?style=flat-square)
![Power Consumption](https://img.shields.io/badge/Power-Zero%20Overhead%20(Metal%20Native)-green?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-lightgrey?style=flat-square)

---

## Release Notes: Version 1.0.2

### Regression Analysis and Resolution
In version 1.0.1, an aggressive sleep-state hook was introduced to minimize standby battery draw. It subscribed to the Darwin notification `com.apple.springboard.hasBlankedScreen` and set `gOverlayWindow.hidden = YES` whenever the display powered down.

#### Root Cause of Failure
On iPadOS 17, the reciprocal wake event `com.apple.springboard.screenIsAwake` is deprecated and no longer broadcast reliably by `SpringBoard` upon user wake or biometric unlock. As a result:
- The window remained in a hidden state (`hidden = YES`) after the screen turned back on.
- The filter ceased displaying until the user navigated to Settings and manually toggled the master enable switch to force a preference reload (`com.ronci.antijaundice/prefsChanged`).

#### Architectural Fix
- **Removal of Redundant State Toggling**: Because version 1.0.1 transitioned all rendering to static `CAGradientLayer` instances with zero timers and no active display links, iOS hardware automatically cuts backlight power and halts compositor scanout when the screen is dark. The overlay consumes 0.0% power during sleep without altering the window hierarchy.
- **Lifecycle Integration**: Subscribed to `UIApplicationDidBecomeActiveNotification` and `UISceneDidActivateNotification`. When the iPad wakes or transitions past the lock screen, the overlay immediately verifies its active window scene and coordinate space bounds without ever dropping visibility.

---

## Release Notes: Version 1.0.1

### Battery and GPU Pipeline Overhaul
- **CoreAnimation GPU Acceleration**: Eliminated software rasterization (`drawRect:`). Gradients are now executed by the GPU via native fragment shaders with 0% CPU consumption.
- **Center Display Bypass**: Converted the fullscreen canvas into 4 independent perimeter boundary layers joined by 45-degree miter masks. The central 90% of the display area contains no sublayers, allowing the iPad Pro 120Hz ProMotion display controller to downclock to 24Hz on static content.
- **Memory Footprint Reduction**: Eliminated dual 2224x1668 32-bit framebuffer allocations, reducing memory usage from approximately 30 MB to under 20 KB.
- **State Gating**: Layout updates are guarded by geometry and parameter equality checks, eliminating redundant transaction commits.

---

## Background: Laminated Panel Edge Degradation

A documented physical aging characteristic in older laminated iPad displays—predominantly the iPad Pro 10.5" (2017), iPad Pro 9.7" (2016), and iPad Air 3rd Gen—is the formation of an amber or brownish border around the screen perimeter.

### Cause of Degradation
Laminated panels bond the cover glass, digitizer, polarizing filter, and TFT LCD substrate using Liquid Optical Clear Adhesive (LOCA/OCA). Over time:
1. **Thermal Exposure**: Edge-mounted LED backlights subject the border adhesive to continuous thermal cycling.
2. **Photo-Oxidation**: Microscopic oxygen diffusion along the bezel perimeter breaks down the polymer matrix, causing discoloration.
3. **Selective Spectral Absorption**: Degraded adhesive acts as an optical low-pass yellow filter, absorbing blue wavelengths (430 nm to 480 nm) while transmitting yellow and red wavelengths.

---

## Technical Approach: Additive Chromatic Inversion

AntiJaundice cancels the defect at the compositor level through complementary chromatic injection:

```
[ Degraded Adhesive: Blue Deficit (Yellow) ] + [ AntiJaundice: Inverted Cool Tint ] = [ Neutral D65 White ]
```

1. **Chromatic Inversion**: A calibrated cold-spectrum gradient is composited along the display perimeter inside the `SpringBoard` render pipeline. Missing blue photons are replenished, restoring D65 white point uniformity.
2. **Non-Linear Feathering**: Multi-stop gradient distributions feather inward toward the unaffected display center to prevent perceptible transition seams.
3. **Contrast Preservation**: Low-alpha additive compositing ensures black levels and movie playback remain unaffected.

---

## Features

- **Continuous Hue Control (`colorHue`: 0 to 100)**:
  - `0.0`: Cyan / Turquoise (~173 deg) for amber and orange degradation.
  - `50.0`: Pure Azure (~227 deg) for standard yellow perimeter aging.
  - `100.0`: Violet-Blue (~281 deg) for dark brownish or greenish borders.
- **Band Width Regulation (`bandWidth`: 50 to 250 px)**: Configures the spatial depth of the compensation gradient to match the affected margin.
- **Edge Offset Calibration (`edgeOffset`: 0 to 40 px)**: Adjusts the outer onset boundary relative to the physical active display border.
- **Precision Intensity Scale (`intensity`: 0.1% to 20.0%)**: Single-decimal percentage tuning for precise chromatic neutralization without blue saturation.
- **Bidirectional Control Synchronization**: Direct real-time synchronization between table cell text fields and slider controls in Settings.
- **Clean Screenshot Interception**: Intercepts `SSScreenCapturer`, `SBScreenshotManager`, and `SpringBoard` screenshot pipelines to hide the overlay during screen capture, ensuring exported media remains unmodified.
- **Input Pass-Through**: Overlay window resides at `UIWindowLevelStatusBar + 50.0` with `_ignoresHitTest` enabled and `userInteractionEnabled = NO`, ensuring zero touch or Apple Pencil latency.

---

## Installation

### Requirements
- **Hardware**: Laminated iPad or iPhone displays exhibiting perimeter discoloration.
- **Firmware**: iOS/iPadOS 12.0 through 18.x.
- **Environment**: Rootless jailbreak environments (Dopamine, palera1n rootless) or rootful configurations.
- **Dependencies**: `preferenceloader`, `mobilesubstrate` (or ElleKit).

### Package Deployment
1. Download the Debian package:
   - `com.ronci.antijaundice_1.0.2_iphoneos-arm64.deb`
2. Install via Sileo, Zebra, or Filza.
3. Perform a userspace reboot or respring.

---

## Calibration Guide

1. Display a uniform white canvas across the screen (for example, a blank document in Safari or Notes).
2. Navigate to **Settings -> AntiJaundice**.
3. Toggle **Enabled** to active.
4. Align the parameters:
   - **Band Width**: Increase the slider until the gradient fully covers the discolored boundary.
   - **Edge Offset**: Align the outer onset with the inner edge of the bezel.
   - **Intensity**: Increase gradually from 0.1% until the yellow cast neutralizes (optimal range is typically between 6.0% and 12.0%).
   - **Color Hue**: Shift toward violet (60-80) if the compensated edge appears green, or toward cyan (20-40) if the edge appears purple.
5. Parameters persist across device reboots and resprings.

---

## Compilation and Packaging

The automated packaging pipeline compiles fat Mach-O binaries for both `arm64` and `arm64e`, establishes entitlement signing, and generates the Debian package:

```bash
cd AntiJaundice
python3 pack_deb.py
```

Pipeline tasks:
1. Compiles `AntiJaundice.dylib` for `SpringBoard` targeting `arm64` and `arm64e`.
2. Signs the dynamic library using `ldid -S`.
3. Compiles the `AntiJaundice` PreferenceBundle against the private Preferences SDK.
4. Generates bundled multi-resolution application icons.
5. Assembles the Debian archive using `dpkg-deb -Zgzip --root-owner-group` to `com.ronci.antijaundice_1.0.2_iphoneos-arm64.deb`.

---

## Repository Structure

```
AntiJaundice/
├── pack_deb.py                     # Build and packaging automation
├── README.md                       # Technical documentation
├── AntiJaundice.plist              # PreferenceLoader root specifier configuration
├── AntiJaundice.m                  # SpringBoard compositor overlay and screenshot hooks
├── AntiJaundicePrefs.m             # Settings preference bundle implementation
├── com.ronci.antijaundice_1.0.2_iphoneos-arm64.deb # Pre-compiled rootless package
└── src/
    ├── AntiJaundice.m              # Primary source mirror
    └── AntiJaundicePrefs.m         # Preferences source mirror
```

---

## Author

- **Developer**: Ronald Nedela ([@RonaldNedela](https://github.com/RonaldNedela))
- **Target Platform**: iPad Pro 10.5" (2017), iPad Pro 9.7", iPad Air 3, iOS/iPadOS 12.0 - 18+

---

## License

This project is licensed under the MIT License.

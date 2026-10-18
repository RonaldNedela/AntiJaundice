# AntiJaundice 🩺

**Optical Edge Yellowing ("Display Jaundice") Compensation Filter for iPad Displays**  
*Targeted chromatic neutralization for degraded LOCA adhesive and polarizer aging on iPad Pro 10.5" (2017), iPad Pro 9.7", iPad Air 3, and all laminated iOS screens.*

![iOS 12.0 - 18+](https://img.shields.io/badge/iOS-12.0--18%2B-blue?style=flat-square)
![Architecture](https://img.shields.io/badge/Architecture-arm64%20%7C%20arm64e-success?style=flat-square)
![Jailbreak](https://img.shields.io/badge/Jailbreak-Rootless%20%26%20Rootful-orange?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-lightgrey?style=flat-square)

---

## 📌 Background: The "Yellow Border" Aging Defect

A widespread issue on older laminated iPad displays—most notoriously the **iPad Pro 10.5-inch (2017)**, **iPad Pro 9.7-inch (2016)**, and **iPad Air 3rd Gen**—is the progressive formation of an unsightly yellow, amber, or brownish border running around the perimeter of the screen. In enthusiast and repair communities, this is colloquially referred to as "display jaundice" or screen adhesive degradation (*"májbetegség"*).

### Why Does It Happen?
Laminated iPad panels bond the outer protective cover glass, digitizer, polarizing filter, and LCD TFT substrate using Liquid Optical Clear Adhesive (LOCA/OCA). Over years of use:
1. **Thermal Stress**: Edge-mounted LED backlights run along the display borders, continuously baking the glue.
2. **Photo-Oxidation & Outgassing**: Microscopic oxygen permeation along the outer perimeter breaks down the polymer chains in the adhesive, causing it to oxidize and turn amber/yellow.
3. **Blue Wavelength Absorption**: The degraded glue acts as an unwanted optical yellow filter, absorbing cold blue spectrum light ($430\text{--}480\,\text{nm}$) and letting only yellow/red pass through at the edges.

Apple repair centers only offer costly full-unit or whole-screen replacements, and refurbished or replacement panels frequently develop the exact same chemical oxidation after a few years.

---

## 💡 The Solution: How AntiJaundice Works

AntiJaundice neutralizes the defect entirely in software through **additive complementary chromatic cancellation**:

```
[ Degraded Glue: Absorbs Blue (Looks Yellow) ] + [ AntiJaundice: Injects Cool Tint ] = [ Neutral D65 White ]
```

1. **Chromatic Inversion**:  
   By projecting a calibrated, inverse cold-spectrum chromatic vignette (gradient bands along the top, bottom, left, and right edges) at the `SpringBoard` compositor level, the tweak compensates for the missing blue photons. The resulting combined transmission across the borders returns to a crisp, neutral white balance.
2. **Smooth Non-Linear Falloff**:  
   The chromatic filter utilizes a smooth cosine/Gaussian gradient curve that gently feathers from the outer bezel inward towards the unaffected center of the screen, ensuring no visible boundary line is perceptible.
3. **True Contrast & Movie Preservation**:  
   The filter is rendered additively with low alpha opacity. In dark mode, during movie playback, or on black backgrounds, dark pixels remain deep and uncolored.

---

## ✨ Features

- 🎨 **Continuous Spectrum Hue Tuning (`colorHue`: 0 – 100)**:
  Unlike tweaks with fixed presets, AntiJaundice features continuous spectrum mapping across the complementary cold spectrum:
  - `0.0`: Cyan / Turquoise ($\approx 173^\circ$) for warm orange/amber edge degradation.
  - `50.0`: Pure Azure / Sky Blue ($\approx 227^\circ$) for classic yellow border aging.
  - `100.0`: Deep Violet-Blue ($\approx 281^\circ$) for brownish or greenish perimeter discoloration.
- 📏 **Band Width Adjustment (`bandWidth`: 50 – 250 px)**:
  Tune the depth of the edge gradient to match whether your panel has a narrow edge fringe or a deep border discoloration.
- 📐 **Edge Offset (`edgeOffset`: 0 – 40 px)**:
  Shift the start of the gradient inward or outward to align perfectly with the physical active display border.
- 🎚️ **Precision Intensity Control (`intensity`: 0.1% – 20.0%)**:
  Allows adjustment down to single-tenth percentages (e.g. `7.5%`) to achieve the exact threshold where yellowing cancels out without over-saturating into blue.
- ⚡ **Real-Time Bidirectional Sync**:
  Dragging any slider updates the companion text box and the SpringBoard screen overlay live with zero lag. You can also type exact numerical values directly.
- 📸 **Automatic Screenshot Clean Capture**:
  Hooks into `SSScreenCapturer`, `SBScreenshotManager`, `SBScreenFlash`, and `SpringBoard` to instantly hide the filter during screenshots and screen recordings. Your captured images remain authentic and defect-free.
- 👆 **Transparent Touch & Apple Pencil Pass-Through**:
  Operates on a non-interactive overlay window (`UIWindowLevelStatusBar + 50.0`) implementing `- (BOOL)_ignoresHitTest` and `userInteractionEnabled = NO`. Zero input latency, zero touch interference.

---

## 🚀 Installation

### Requirements
- **Device**: Any iPad or iPhone with laminated display edge yellowing (specifically optimized for iPad Pro 10.5" 2017).
- **Firmware**: iOS 12.0 up to iOS 18+.
- **Jailbreak**: Dopamine, palera1n, XinaA15, unc0ver, checkra1n, Taurine, etc.
- **Dependencies**: `mobilesubstrate` (or ElleKit), `preferenceloader`.

### Package Manager (Sileo / Zebra / Filza)
1. Download the compiled `.deb` package:
   - **Rootless (Dopamine / palera1n rootless):**  
     `com.ronci.antijaundice_1.0.0_iphoneos-arm64.deb`
2. Open in **Sileo** / **Zebra** / **Filza** and tap **Install**.
3. Respring your device.

---

## 🛠️ Step-by-Step Calibration Walkthrough

1. Open a pure white background on your iPad (e.g., a blank page in **Safari**, **Notes**, or **Apple Books** in light mode).
2. Open **Settings ➔ AntiJaundice**.
3. Switch **Enabled** to `ON`.
4. Observe the yellow border along the screen edges:
   - **Band Width**: Adjust the slider until the blue gradient band covers the full width of the yellowing border.
   - **Edge Offset**: Set the offset so the gradient begins precisely where the yellowing starts along the bezel.
   - **Intensity**: Slowly raise intensity from `0.1%` up until the yellow tint neutralizes. (Typical sweet spot is between `6.0%` and `12.0%`).
   - **Color Hue**: If the border looks slightly greenish after adding the filter, slide **Color Hue** higher towards `60–80` (more violet). If it looks too purple, slide lower towards `20–40` (more cyan).
5. The calibration is stored permanently across resprings and reboots!

---

## 🏗️ Building from Source

To compile the Fat Mach-O dylib and preference bundle for both `arm64` and `arm64e`, and package the Debian archive:

```bash
# Navigate to the AntiJaundice directory
cd AntiJaundice

# Run the python packaging pipeline
python3 pack_deb.py
```

The script:
1. Compiles `AntiJaundice.dylib` for SpringBoard using Xcode clang with `-arch arm64 -arch arm64e`.
2. Links and codesigns the dylib via `ldid -S`.
3. Compiles `AntiJaundice` PreferenceBundle Mach-O linked to `Preferences.tbd`.
4. Generates multi-resolution Settings icons.
5. Builds the `.deb` archive via `dpkg-deb -Zgzip --root-owner-group` to `/Users/Ronci/Downloads/com.ronci.antijaundice_1.0.0_iphoneos-arm64.deb`.

---

## 📂 Project Structure

```
AntiJaundice/
├── pack_deb.py                     # Automated fat compiler & deb packager
├── README.md                       # Complete documentation
├── AntiJaundice.plist              # PreferenceLoader root specifier plist
└── src/
    ├── AntiJaundice.m              # SpringBoard compositor hook, vignette renderer & screenshot suppression
    └── AntiJaundicePrefs.m         # PreferenceBundle controller with bidirectional slider sync
```

---

## 👤 Author

- **Developer**: Ronci
- **Compatibility**: iPad Pro 10.5" (2017) • iPad Pro 9.7" • iPad Air 3 • iOS 12.0 – 18+

---

## 📄 License

This project is licensed under the MIT License - feel free to modify, distribute, and integrate.

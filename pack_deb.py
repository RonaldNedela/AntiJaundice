#!/usr/bin/env python3
import os
import sys
import subprocess
import shutil
from PIL import Image, ImageDraw

script_dir = os.path.dirname(os.path.abspath(__file__))
source_sb_m = os.path.join(script_dir, "src/AntiJaundice.m")
source_pref_m = os.path.join(script_dir, "src/AntiJaundicePrefs.m")

if not os.path.exists(source_sb_m):
    print(f"Error: SpringBoard source file not found at {source_sb_m}")
    sys.exit(1)

if not os.path.exists(source_pref_m):
    print(f"Error: Preferences source file not found at {source_pref_m}")
    sys.exit(1)

build_dir = "/tmp/antijaundice_build"
layout_dir = os.path.join(build_dir, "layout")

if os.path.exists(layout_dir):
    shutil.rmtree(layout_dir)
os.makedirs(build_dir, exist_ok=True)

# Layout folders for Rootless architecture
sub_dir = os.path.join(layout_dir, "var/jb/Library/MobileSubstrate/DynamicLibraries")
pref_bundle_dir = os.path.join(layout_dir, "var/jb/Library/PreferenceBundles/AntiJaundice.bundle")
pref_loader_dir = os.path.join(layout_dir, "var/jb/Library/PreferenceLoader/Preferences")
ctrl_dir = os.path.join(layout_dir, "DEBIAN")

os.makedirs(sub_dir, exist_ok=True)
os.makedirs(pref_bundle_dir, exist_ok=True)
os.makedirs(pref_loader_dir, exist_ok=True)
os.makedirs(ctrl_dir, exist_ok=True)

# 1. Compile SpringBoard dylib (fat arm64 + arm64e)
dylib_src = os.path.join(build_dir, "AntiJaundice.dylib")
cmd_compile_sb = [
    "xcrun", "-sdk", "iphoneos", "clang", "-dynamiclib",
    "-arch", "arm64", "-arch", "arm64e",
    "-miphoneos-version-min=15.0",
    "-fobjc-arc", "-O2",
    "-framework", "UIKit", "-framework", "Foundation",
    "-framework", "CoreGraphics", "-framework", "QuartzCore", "-framework", "CoreFoundation",
    "-install_name", "/var/jb/Library/MobileSubstrate/DynamicLibraries/AntiJaundice.dylib",
    "-o", dylib_src,
    source_sb_m
]
print("Compiling SpringBoard dylib from:", source_sb_m)
subprocess.run(cmd_compile_sb, check=True)
subprocess.run(["ldid", "-S", dylib_src], check=True)

dylib_dst = os.path.join(sub_dir, "AntiJaundice.dylib")
shutil.copy2(dylib_src, dylib_dst)
os.chmod(dylib_dst, 0o755)

# 2. Create MobileSubstrate filter plist for SpringBoard
filter_plist = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Filter</key>
    <dict>
        <key>Bundles</key>
        <array>
            <string>com.apple.springboard</string>
        </array>
    </dict>
</dict>
</plist>
"""
filter_dst = os.path.join(sub_dir, "AntiJaundice.plist")
with open(filter_dst, "w", encoding="utf-8") as f:
    f.write(filter_plist)
os.chmod(filter_dst, 0o644)

# 3. Create Preferences.tbd stub to link Preferences.framework with two-level namespace
tbd_path = os.path.join(build_dir, "Preferences.tbd")
with open(tbd_path, "w", encoding="utf-8") as f:
    f.write("""--- !tapi-tbd
tbd-version:     4
targets:         [ arm64-ios, arm64e-ios ]
install-name:    '/System/Library/PrivateFrameworks/Preferences.framework/Preferences'
current-version: 1.0
exports:
  - targets:         [ arm64-ios, arm64e-ios ]
    symbols:         [ _OBJC_CLASS_$_PSListController,
                       _OBJC_METACLASS_$_PSListController,
                       _OBJC_CLASS_$_PSTableCell,
                       _OBJC_METACLASS_$_PSTableCell,
                       _OBJC_CLASS_$_PSSpecifier,
                       _OBJC_METACLASS_$_PSSpecifier ]
...
""")

# 4. Compile PreferenceBundle binary (fat arm64 + arm64e) linked to Preferences.framework
pref_bin_src = os.path.join(build_dir, "AntiJaundicePrefs_bin")
cmd_compile_prefs = [
    "xcrun", "-sdk", "iphoneos", "clang", "-bundle",
    "-arch", "arm64", "-arch", "arm64e",
    "-miphoneos-version-min=15.0",
    "-fobjc-arc", "-O2",
    "-framework", "UIKit", "-framework", "Foundation",
    "-framework", "CoreGraphics", "-framework", "CoreFoundation",
    tbd_path,
    "-o", pref_bin_src,
    source_pref_m
]
print("Compiling PreferenceBundle binary linked to Preferences.framework from:", source_pref_m)
subprocess.run(cmd_compile_prefs, check=True)
subprocess.run(["ldid", "-S", pref_bin_src], check=True)

pref_bin_dst = os.path.join(pref_bundle_dir, "AntiJaundice")
shutil.copy2(pref_bin_src, pref_bin_dst)
os.chmod(pref_bin_dst, 0o755)

# 5. Create PreferenceBundle Info.plist
bundle_info_plist = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.ronci.antijaundice.prefs</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>AntiJaundice</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>NSPrincipalClass</key>
    <string>AntiJaundiceRootListController</string>
</dict>
</plist>
"""
with open(os.path.join(pref_bundle_dir, "Info.plist"), "w", encoding="utf-8") as f:
    f.write(bundle_info_plist)
os.chmod(os.path.join(pref_bundle_dir, "Info.plist"), 0o644)

# 6. Copy AntiJaundice.plist as Root.plist inside bundle, and entry plist in PreferenceLoader
plist_source = os.path.join(script_dir, "AntiJaundice.plist")
with open(plist_source, "r", encoding="utf-8") as f:
    spec_plist_content = f.read()

# Write Root.plist in AntiJaundice.bundle
root_plist_path = os.path.join(pref_bundle_dir, "Root.plist")
with open(root_plist_path, "w", encoding="utf-8") as f:
    f.write(spec_plist_content)
os.chmod(root_plist_path, 0o644)

# Write ONLY one AntiJaundice.plist directly in PreferenceLoader/Preferences/ (prevents duplicate in Settings sidebar)
with open(os.path.join(pref_loader_dir, "AntiJaundice.plist"), "w", encoding="utf-8") as f:
    f.write(spec_plist_content)
os.chmod(os.path.join(pref_loader_dir, "AntiJaundice.plist"), 0o644)

# 7. Generate Preferences Icons
def make_icon(size, out_path):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    border_r = int(size * 0.22)
    draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=border_r, fill=(0, 122, 255, 255))
    inset = int(size * 0.2)
    draw.rounded_rectangle([inset, inset, size - 1 - inset, size - 1 - inset], radius=int(size * 0.08), outline=(255, 255, 255, 240), width=max(1, int(size * 0.06)))
    center = size // 2
    r_dot = max(2, int(size * 0.08))
    draw.ellipse([center - r_dot, center - r_dot, center + r_dot, center + r_dot], fill=(255, 255, 255, 240))
    img.save(out_path, "PNG")
    os.chmod(out_path, 0o644)

for d in [pref_bundle_dir, pref_loader_dir]:
    make_icon(29, os.path.join(d, "AntiJaundice.png"))
    make_icon(58, os.path.join(d, "AntiJaundice@2x.png"))
    make_icon(87, os.path.join(d, "AntiJaundice@3x.png"))
    make_icon(29, os.path.join(d, "icon.png"))
    make_icon(58, os.path.join(d, "icon@2x.png"))
    make_icon(87, os.path.join(d, "icon@3x.png"))

# 8. Control file
control_content = """Package: com.ronci.antijaundice
Name: AntiJaundice
Version: 1.0.0
Architecture: iphoneos-arm64
Description: Screen edge yellowing compensation filter for iPad.
Maintainer: Ronci
Author: Ronci
Section: Tweaks
Depends: mobilesubstrate (>= 0.9.5000), preferenceloader
Tag: role::tweaks, purpose::extension
"""
ctrl_file = os.path.join(ctrl_dir, "control")
with open(ctrl_file, "w", encoding="utf-8") as f:
    f.write(control_content)
os.chmod(ctrl_file, 0o644)

# 9. Postinst script (Cleans up previous duplicate subfolder, prompts Respring, kills Preferences)
postinst_content = """#!/bin/sh
set -e

if [ "$1" = "configure" ]; then
    # Clean up old subfolder from previous versions to prevent duplicate Settings entries
    rm -rf /var/jb/Library/PreferenceLoader/Preferences/AntiJaundice 2>/dev/null || true

    # Close Settings if running so it re-reads new preference bundle immediately
    killall -9 Preferences 2>/dev/null || true

    # Tell Cydia / Sileo / Zebra to prompt for Respring
    if [ -n "$CYDIA" ]; then
        cydia_fd=$(echo "$CYDIA" | cut -d' ' -f1)
        if [ -n "$cydia_fd" ]; then
            eval "echo 'finish:restart' >&$cydia_fd" 2>/dev/null || true
        fi
    fi

    # Terminal / CLI install fallback (when not inside a GUI package manager)
    if [ -z "$CYDIA" ] && [ -t 1 ]; then
        if [ -x "/var/jb/usr/bin/sbreload" ]; then
            /var/jb/usr/bin/sbreload 2>/dev/null || killall -9 SpringBoard 2>/dev/null || true
        elif command -v sbreload >/dev/null 2>&1; then
            sbreload 2>/dev/null || killall -9 SpringBoard 2>/dev/null || true
        else
            killall -9 SpringBoard 2>/dev/null || true
        fi
    fi
fi

exit 0
"""
postinst_file = os.path.join(ctrl_dir, "postinst")
with open(postinst_file, "w", encoding="utf-8") as f:
    f.write(postinst_content)
os.chmod(postinst_file, 0o755)

# 10. Postrm script
postrm_content = """#!/bin/sh
set -e

if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
    rm -rf /var/jb/Library/PreferenceLoader/Preferences/AntiJaundice 2>/dev/null || true
    killall -9 Preferences 2>/dev/null || true

    if [ -n "$CYDIA" ]; then
        cydia_fd=$(echo "$CYDIA" | cut -d' ' -f1)
        if [ -n "$cydia_fd" ]; then
            eval "echo 'finish:restart' >&$cydia_fd" 2>/dev/null || true
        fi
    fi

    if [ -z "$CYDIA" ] && [ -t 1 ]; then
        if [ -x "/var/jb/usr/bin/sbreload" ]; then
            /var/jb/usr/bin/sbreload 2>/dev/null || killall -9 SpringBoard 2>/dev/null || true
        elif command -v sbreload >/dev/null 2>&1; then
            sbreload 2>/dev/null || killall -9 SpringBoard 2>/dev/null || true
        else
            killall -9 SpringBoard 2>/dev/null || true
        fi
    fi
fi

exit 0
"""
postrm_file = os.path.join(ctrl_dir, "postrm")
with open(postrm_file, "w", encoding="utf-8") as f:
    f.write(postrm_content)
os.chmod(postrm_file, 0o755)

# 11. Build package using official dpkg-deb with GNU gzip compression and root owner
deb_output = "/Users/Ronci/Downloads/com.ronci.antijaundice_1.0.0_iphoneos-arm64.deb"
print(f"Building deb package via dpkg-deb to {deb_output}...")
cmd_deb = [
    "dpkg-deb",
    "-Zgzip",
    "--root-owner-group",
    "-b", layout_dir,
    deb_output
]
subprocess.run(cmd_deb, check=True)

print(f"Package successfully created at: {deb_output}")
print(f"File size: {os.path.getsize(deb_output)} bytes")

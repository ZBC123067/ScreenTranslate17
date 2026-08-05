#!/usr/bin/env python3
"""Dependency-free preflight checks for the RootHide source package.

This validates source/package invariants only. It cannot replace an arm64e
compile with RootHide Theos or an on-device injection test.
"""
from __future__ import annotations

import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []


def require(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


def read_text(path: Path) -> str:
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError as exc:
        errors.append(f"{path.relative_to(ROOT)} is not valid UTF-8: {exc}")
        return ""
    require("\ufffd" not in text, f"{path.relative_to(ROOT)} contains a replacement character")
    return text


def objc_strings_balanced(text: str) -> bool:
    """Reject unclosed C/Objective-C string and block-comment literals."""
    state = "code"
    index = 0
    while index < len(text):
        char = text[index]
        next_char = text[index + 1] if index + 1 < len(text) else ""
        if state == "code":
            if char == "/" and next_char == "/":
                state, index = "line-comment", index + 1
            elif char == "/" and next_char == "*":
                state, index = "block-comment", index + 1
            elif char == '"':
                state = "string"
        elif state == "line-comment":
            if char == "\n":
                state = "code"
        elif state == "block-comment":
            if char == "*" and next_char == "/":
                state, index = "code", index + 1
        elif state == "string":
            if char == "\\":
                index += 1
            elif char == '"':
                state = "code"
        index += 1
    return state == "code"


all_text: dict[Path, str] = {}
for path in ROOT.rglob("*"):
    if ".git" in path.parts:
        continue
    if not path.is_file() or path.name == "icon.png":
        continue
    if path.suffix in {".m", ".h", ".xm", ".md", ".yml", ".plist", ""}:
        all_text[path] = read_text(path)

for path, text in all_text.items():
    if path.suffix in {".m", ".h", ".xm"}:
        require(objc_strings_balanced(text), f"{path.relative_to(ROOT)} has an unclosed string or block comment")

for path in ROOT.rglob("*.plist"):
    data = path.read_bytes().lstrip()
    if data.startswith(b"<?xml"):
        try:
            plistlib.loads(data)
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{path.relative_to(ROOT)} is not a valid XML plist: {exc}")

makefile = read_text(ROOT / "Makefile")
control = read_text(ROOT / "control")
readme = read_text(ROOT / "README.md")
workflow = read_text(ROOT / ".github/workflows/build.yml")
tweak = read_text(ROOT / "Tweak.xm")
privacy = read_text(ROOT / "Sources/STPrivacy.m")
cache = read_text(ROOT / "Sources/STCache.m")
manager = read_text(ROOT / "Sources/STManager.m")
translation = read_text(ROOT / "Sources/STTranslationService.m")
input_helper = read_text(ROOT / "Sources/STInputHelper.m")
root_specs = plistlib.loads((ROOT / "Preferences/Resources/Root.plist").read_bytes())
info = plistlib.loads((ROOT / "Preferences/Info.plist").read_bytes())
entitlements = plistlib.loads((ROOT / "entitlements.plist").read_bytes())

require("THEOS_PACKAGE_SCHEME = roothide" in makefile, "Makefile must use the RootHide package scheme")
require("ARCHS = arm64e" in makefile, "Makefile must target arm64e")
require("ScreenTranslate17_ENTITLEMENTS = entitlements.plist" in makefile, "tweak entitlements are missing")
require("ScreenTranslate17Prefs_ENTITLEMENTS = entitlements.plist" in makefile, "preferences-bundle entitlements are missing")
require("Sources/STPrivacy.m Sources/STTranslationService.m" in makefile, "preferences bundle cannot compile the service-test action")
require("internal-stage::" in makefile and "Preferences/entry.plist" in makefile, "PreferenceLoader staging rule is missing")
layout = ROOT / "layout"
require(not (layout / "Library").exists(), "layout/Library duplicates PreferenceLoader staging")
postinst = layout / "DEBIAN" / "postinst"
require(postinst.is_file(), "package post-install script is missing")
postinst_text = read_text(postinst) if postinst.is_file() else ""
require("killall -9 Preferences" in postinst_text, "post-install script does not refresh Settings")
require("Architecture: iphoneos-arm64e" in control, "control architecture is not arm64e")
require("Version: 0.4.1" in control and "ScreenTranslate17 0.4.1" in readme, "version strings are inconsistent")
require(info.get("CFBundleShortVersionString") == "0.4.1", "preference bundle version is inconsistent")
require(info.get("CFBundleExecutable") == "ScreenTranslate17Prefs", "preference bundle executable is incorrect")
require(info.get("CFBundleDisplayName") == "ScreenTranslate17", "preference bundle display name is incorrect")
require(info.get("MinimumOSVersion") == "15.0", "preference bundle minimum OS version is incorrect")
require("com.apple.UIKit" in read_text(ROOT / "ScreenTranslate17.plist"), "UIKit injection filter is missing")
require("com.apple.springboard" in tweak, "SpringBoard exclusion is missing")
require("google_web" not in "\n".join(all_text.values()), "removed Google Web provider remains in source")
for key in [
    "platform-application",
    "com.apple.private.security.no-sandbox",
    "com.apple.private.security.storage.AppBundles",
    "com.apple.private.security.storage.AppDataContainers",
]:
    require(entitlements.get(key) is True, f"missing RootHide entitlement: {key}")

api_key_spec = next((item for item in root_specs if item.get("key") == "apiKey"), {})
require(api_key_spec.get("isSecure") is True, "API Key preference is not secure-display")
require(any(item.get("action") == "testService" for item in root_specs), "cache-bypassing service test action is missing")
require("bypassCache:(BOOL)bypassCache" in translation, "translation service cannot bypass cache for tests")
require("STCurrentPageIdentity" in manager and "operationGeneration" in manager, "stale callback protection is missing")
require("eligibilityForGeneration" in manager and "isEligibleForNetwork" in translation, "pre-send privacy recheck is missing")
require("NSProcessInfoThermalStateDidChangeNotification" in manager, "thermal pause observer is missing")
require("NSMutableOrderedSet" in manager and "chatRetryAfter" in manager, "chat retry bookkeeping is missing")
require("ST_PRIVATE_" in privacy and "textContainsSensitiveData" in privacy, "collision-safe sensitive placeholders are missing")
require("redaction-on" in cache and "STCacheClearedDarwinNotification" in cache, "cache privacy isolation or clear propagation is missing")
require("STWithFileLock" in cache and "STWithFileLock" in read_text(ROOT / "Sources/STPreferences.m"), "cross-process write locking is missing")
require("replaceInput:" in input_helper and "ifCurrentTextEquals" in input_helper, "input replacement identity check is missing")
preferences = read_text(ROOT / "Sources/STPreferences.m")
overlay = read_text(ROOT / "Sources/STOverlayManager.m")
require("singleTapAction" in preferences and "doubleTapAction" in preferences, "tap-action preferences are missing")
require("didRequestConfiguredAction" in overlay and "doubleTapped" in overlay, "configured tap dispatch is missing")
require("firstTranslationError" in manager and "receivedTranslation" in manager, "failed translations are not surfaced to the user")
require("dpkg-deb" not in workflow, "macOS workflow must not depend on dpkg-deb")
for marker in ["ar -x", "data.tar.*", "control.tar.*", "postinst", "PreferenceLoader", "lipo -archs", "ScreenTranslate17Prefs"]:
    require(marker in workflow, f"workflow does not validate final package marker: {marker}")

for path in re.findall(r"(?:Tweak\.xm|[A-Za-z0-9_./-]+\.m)", makefile):
    if path.startswith("/") or "makefiles/" in path:
        continue
    require((ROOT / path).is_file(), f"Makefile references missing source file: {path}")

entry = read_text(ROOT / "Preferences/entry.plist")
require("bundle = ScreenTranslate17Prefs" in entry and "detail = STRootListController" in entry, "PreferenceLoader entry is invalid")
require("id = ScreenTranslate17" in entry, "PreferenceLoader entry has no stable Settings identifier")
require("replaceCurrentTextWithString" not in "\n".join(all_text.values()), "obsolete unsafe input replacement remains")
require("CGImageRelease(cropped);\n            STDispatchMain" not in "\n".join(all_text.values()), "possible old OCR double-release pattern remains")

if errors:
    print("Static audit failed:", file=sys.stderr)
    print("\n".join(f"- {error}" for error in errors), file=sys.stderr)
    raise SystemExit(1)
print("Static audit passed.")

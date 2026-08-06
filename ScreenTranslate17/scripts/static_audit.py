#!/usr/bin/env python3
"""Fast, dependency-free preflight checks run before the RootHide build."""
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


for path in ROOT.rglob("*"):
    if path.is_file() and path.suffix in {".m", ".h", ".xm", ".md", ".yml", ".plist", ""}:
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError as exc:
            errors.append(f"{path.relative_to(ROOT)} is not valid UTF-8: {exc}")
            continue
        require("\ufffd" not in text, f"{path.relative_to(ROOT)} contains a replacement character")

for relative in ["entitlements.plist", "Preferences/Info.plist", "Preferences/Resources/Root.plist"]:
    try:
        plistlib.loads((ROOT / relative).read_bytes())
    except Exception as exc:  # noqa: BLE001
        errors.append(f"{relative} is not a valid XML plist: {exc}")

makefile = (ROOT / "Makefile").read_text(encoding="utf-8")
control = (ROOT / "control").read_text(encoding="utf-8")
readme = (ROOT / "README.md").read_text(encoding="utf-8")
tweak = (ROOT / "Tweak.xm").read_text(encoding="utf-8")
workflow_path = ROOT / ".github/workflows/build.yml"
if not workflow_path.exists():
    workflow_path = ROOT.parent / ".github/workflows/build.yml"
workflow = workflow_path.read_text(encoding="utf-8")
entitlements = plistlib.loads((ROOT / "entitlements.plist").read_bytes())
info_plist = plistlib.loads((ROOT / "Preferences/Info.plist").read_bytes())

require("THEOS_PACKAGE_SCHEME = roothide" in makefile, "Makefile must use the RootHide package scheme")
require("ARCHS = arm64e" in makefile, "Makefile must target arm64e")
require("ScreenTranslate17_ENTITLEMENTS = entitlements.plist" in makefile, "tweak entitlements are missing")
require("ScreenTranslate17Prefs_ENTITLEMENTS = entitlements.plist" in makefile, "preferences-bundle entitlements are missing")
require("Architecture: iphoneos-arm64e" in control, "control architecture is not arm64e")
version_match = re.search(r"^Version:\s*(\S+)", control, re.MULTILINE)
version = version_match.group(1) if version_match else ""
require(bool(version), "control version is missing")
require(version in readme, "README version is inconsistent")
require(info_plist.get("CFBundleShortVersionString") == version, "preferences bundle version is inconsistent")
require("com.apple.UIKit" in (ROOT / "ScreenTranslate17.plist").read_text(encoding="utf-8"), "UIKit injection filter is missing")
require("com.apple.springboard" in tweak, "SpringBoard exclusion is missing")
require("PROJECT_DIR=ScreenTranslate17" in workflow and 'cd "$PROJECT_DIR"' in workflow, "workflow does not support the repository subdirectory layout")
for key in [
    "platform-application",
    "com.apple.private.security.no-sandbox",
    "com.apple.private.security.storage.AppBundles",
    "com.apple.private.security.storage.AppDataContainers",
]:
    require(entitlements.get(key) is True, f"missing RootHide entitlement: {key}")

source = "\n".join(path.read_text(encoding="utf-8") for path in (ROOT / "Sources").glob("*.[mh]"))
manager = (ROOT / "Sources/STManager.m").read_text(encoding="utf-8")
overlay = (ROOT / "Sources/STOverlayManager.m").read_text(encoding="utf-8")
ocr = (ROOT / "Sources/STOCRService.m").read_text(encoding="utf-8")
require("google_web" not in source, "removed Google Web provider remains in source")
require("recognizeCurrentScreenInRegion:CGRectZero completion" not in source, "obsolete OCR call remains")
require("CGImageRelease(cropped);\n            STDispatchMain" not in source, "possible old OCR double-release pattern remains")
require("presentControlPanelWithContinuousActive:self.continuousActive chatActive:self.chatActive" in overlay, "control panel does not receive live mode state")
require("self.densePresentation = YES" in overlay and "rebuildReadingPanel" in overlay, "dense-page non-overlapping layout fallback is missing")
require("supportedRecognitionLanguagesForTextRecognitionLevel" in ocr, "OCR languages are not filtered against Vision support")
require("continuousOCRInFlight" in manager and "chatOCRInFlight" in manager, "OCR re-entry guards are missing")
require("nativeFresh == 0" in manager and "recognizeCurrentScreenInRegion:CGRectNull fast:YES" in manager, "chat OCR fallback is missing")
require("![fingerprint isEqualToString:self.lastVisualFingerprint]" not in manager, "old two-identical-frame subtitle gate remains")


def balanced_delimiters(path: Path) -> bool:
    """Lightweight source sanity check; ignores comments and quoted literals."""
    text = path.read_text(encoding="utf-8")
    text = re.sub(r'@"(?:\\.|[^"\\])*"', '""', text)
    text = re.sub(r'"(?:\\.|[^"\\])*"', '""', text)
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
    text = re.sub(r"//[^\n]*", "", text)
    pairs = {")": "(", "]": "[", "}": "{"}
    stack: list[str] = []
    for character in text:
        if character in "([{":
            stack.append(character)
        elif character in pairs:
            if not stack or stack.pop() != pairs[character]:
                return False
    return not stack


for path in list((ROOT / "Sources").glob("*.[mh]")) + [ROOT / "Tweak.xm", ROOT / "Preferences/STRootListController.m"]:
    require(balanced_delimiters(path), f"{path.relative_to(ROOT)} has unbalanced delimiters")

if errors:
    print("Static audit failed:", file=sys.stderr)
    print("\n".join(f"- {error}" for error in errors), file=sys.stderr)
    raise SystemExit(1)
print("Static audit passed.")

"""Validate ReefRun's explicit rewarded-ad mode. Does not request an ad."""

import argparse
import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
ANDROID_APP_ID = "ca-app-pub-5190108736982657~2452653885"
IOS_APP_ID = "ca-app-pub-5190108736982657~5175195159"
ANDROID_TEST_UNIT = "ca-app-pub-3940256099942544/5224354917"
IOS_TEST_UNIT = "ca-app-pub-3940256099942544/1712485313"
ANDROID_LIVE_UNIT = "ca-app-pub-5190108736982657/3355591884"
IOS_LIVE_UNIT = "ca-app-pub-5190108736982657/2549031818"


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def const_string(source: str, name: str) -> str:
    match = re.search(rf'const {name} := "([^"]*)"', source)
    if match is None:
        fail(f"{name} was not found.")
    return match.group(1)


def check_source(platform: str, mode: str) -> str:
    if platform not in ("ios", "android"):
        fail("Pass --platform ios or --platform android. One mode no longer applies to both stores.")
    if mode not in ("test", "production"):
        fail(f"Unsupported ad mode {mode!r}. Use test or production.")
    build = (ROOT / "scripts/ads/ad_build_mode.gd").read_text(encoding="utf-8")
    ads = (ROOT / "scripts/ads/ad_config.gd").read_text(encoding="utf-8")
    project = (ROOT / "project.godot").read_text(encoding="utf-8")
    ios_mode = const_string(build, "IOS_MODE")
    android_mode = const_string(build, "ANDROID_MODE")
    ios_marker = const_string(build, "IOS_OUTPUT_MARKER")
    android_marker = const_string(build, "ANDROID_OUTPUT_MARKER")
    if ios_mode not in ("test", "production") or android_mode not in ("test", "production"):
        fail("IOS_MODE and ANDROID_MODE must each be exactly test or production.")
    if ios_marker != f"REEFRUN_IOS_AD_MODE={ios_mode}":
        fail(f"IOS_OUTPUT_MARKER is {ios_marker!r}.")
    if android_marker != f"REEFRUN_ANDROID_AD_MODE={android_mode}":
        fail(f"ANDROID_OUTPUT_MARKER is {android_marker!r}.")
    packed = ios_mode if platform == "ios" else android_mode
    marker = ios_marker if platform == "ios" else android_marker
    if platform == "ios" and android_mode != "test":
        fail(
            "This iOS export requires ANDROID_MODE to stay \"test\". "
            f"It is {android_mode!r}, so the same source would request live Android ads."
        )
    if mode != packed:
        fail(
            f"The {platform} workflow was started in {mode!r}, but "
            f"scripts/ads/ad_build_mode.gd says {packed!r}. Refusing to build."
        )
    if "const MODE :=" in build:
        fail("Remove the old shared MODE. Ads are selected per platform.")
    selector = ads.split("static func rewarded_unit_for", 1)[-1].split("static func rewarded_unit_id", 1)[0]
    if 'normalize_mode(mode) != "production"' not in selector or "return test_unit" not in selector:
        fail("Test mode must return the Google test rewarded unit.")
    if "is_google_test_rewarded_unit(production)" not in selector:
        fail("Production mode must refuse a Google sample rewarded unit.")
    if "mode_for_platform" not in ads:
        fail("ad_config.gd must select the rewarded unit from the platform mode.")
    for required in (
        ANDROID_TEST_UNIT,
        IOS_TEST_UNIT,
        ANDROID_LIVE_UNIT,
        IOS_LIVE_UNIT,
        ANDROID_APP_ID,
        IOS_APP_ID,
    ):
        if required not in ads:
            fail(f"ad_config.gd is missing {required}.")
    if f'general/android/app_id="{ANDROID_APP_ID}"' not in project:
        fail("project.godot is missing the production Android AdMob app id.")
    if f'general/ios/app_id="{IOS_APP_ID}"' not in project:
        fail("project.godot is missing the production iOS AdMob app id.")
    selected = IOS_LIVE_UNIT if platform == "ios" and packed == "production" else ""
    if platform == "ios" and packed == "test":
        selected = IOS_TEST_UNIT
    if platform == "android" and packed == "test":
        selected = ANDROID_TEST_UNIT
    if platform == "android" and packed == "production":
        selected = ANDROID_LIVE_UNIT
    print(
        f"{platform} ad mode is {packed}. Android mode is {android_mode}. "
        f"iOS mode is {ios_mode}. Selected rewarded unit is {selected}."
    )
    return marker


def check_manifest(text: str) -> None:
    if ANDROID_APP_ID not in text:
        fail("The exported Android manifest does not contain the production AdMob app id.")
    if "com.google.android.gms.permission.AD_ID" not in text:
        fail("The exported Android manifest does not declare com.google.android.gms.permission.AD_ID.")
    if "android.permission.INTERNET" not in text:
        fail("The exported Android manifest does not declare android.permission.INTERNET.")


def package_files(path: pathlib.Path) -> list[pathlib.Path]:
    if path.is_file():
        return [path]
    if not path.is_dir():
        fail(f"Build output was not found: {path}")
    found = [
        item
        for item in path.rglob("*")
        if item.is_file() and item.suffix.lower() in {".pck", ".apk", ".aab", ".ipa"}
    ]
    if not found:
        fail(f"No exported pck, apk, aab, or ipa was found under {path}.")
    return found


def check_packages(paths: list[str], marker: str) -> None:
    if marker.startswith("REEFRUN_IOS_AD_MODE="):
        wrong = "REEFRUN_IOS_AD_MODE=production" if marker.endswith("=test") else "REEFRUN_IOS_AD_MODE=test"
    elif marker.startswith("REEFRUN_ANDROID_AD_MODE="):
        wrong = "REEFRUN_ANDROID_AD_MODE=production" if marker.endswith("=test") else "REEFRUN_ANDROID_AD_MODE=test"
    else:
        fail(f"Unrecognized ad-mode marker {marker!r}.")
    marker_bytes = marker.encode("utf-8")
    wrong_bytes = wrong.encode("utf-8")
    saw_marker = False
    for raw in paths:
        for package in package_files(pathlib.Path(raw)):
            blob = package.read_bytes()
            if wrong_bytes in blob:
                fail(f"{package} contains {wrong}, which does not match this build.")
            if marker_bytes in blob:
                saw_marker = True
                print(f"Found {marker} in {package}.")
    if not saw_marker:
        print(
            "UNVERIFIED: the ad-mode marker was not readable in the exported package. "
            "Godot may have compressed it. The source mode was validated before export."
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", required=True, choices=("ios", "android"))
    parser.add_argument("--mode", default="test")
    parser.add_argument("--manifest", action="append", default=[])
    parser.add_argument("--manifest-file", action="append", default=[])
    parser.add_argument("--package", action="append", default=[])
    args = parser.parse_args()
    mode = (args.mode or "test").strip().lower()
    if mode == "":
        mode = "test"
    marker = check_source(args.platform, mode)
    for manifest in args.manifest:
        check_manifest(manifest)
    for manifest_path in args.manifest_file:
        check_manifest(pathlib.Path(manifest_path).read_text(encoding="utf-8", errors="replace"))
    if args.package:
        check_packages(args.package, marker)


if __name__ == "__main__":
    main()

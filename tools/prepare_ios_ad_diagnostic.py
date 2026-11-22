"""Point one iOS checkout at Google's official rewarded test unit.

Rewrites only the packed iOS mode to "diagnostic". The production unit id, the
Android mode, and the iOS AdMob app id stay where they are. The result is for
an internal TestFlight build. Do not commit it, and do not submit that build
for App Store release.
"""

import argparse
import pathlib
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
MODE_FILE = ROOT / "scripts" / "ads" / "ad_build_mode.gd"
CONFIG_FILE = ROOT / "scripts" / "ads" / "ad_config.gd"
PROJECT_FILE = ROOT / "project.godot"
DEMO_UNIT = "ca-app-pub-3940256099942544/1712485313"
PRODUCTION_UNIT = "ca-app-pub-5190108736982657/2549031818"
IOS_APP_ID = "ca-app-pub-5190108736982657~5175195159"
PRODUCTION_MODE = 'const IOS_MODE := "production"'
DIAGNOSTIC_MODE = 'const IOS_MODE := "diagnostic"'
PRODUCTION_MARKER = 'const IOS_OUTPUT_MARKER := "REEFRUN_IOS_AD_MODE=production"'
DIAGNOSTIC_MARKER = 'const IOS_OUTPUT_MARKER := "REEFRUN_IOS_AD_MODE=diagnostic"'


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--confirm-demo-unit", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    if not args.confirm_demo_unit:
        fail("Refusing to change the iOS ad mode without --confirm-demo-unit.")
    mode_text = MODE_FILE.read_text(encoding="utf-8")
    config_text = CONFIG_FILE.read_text(encoding="utf-8")
    project_text = PROJECT_FILE.read_text(encoding="utf-8")
    if PRODUCTION_UNIT not in config_text or DEMO_UNIT not in config_text:
        fail("ad_config.gd no longer contains both the production unit and Google's test unit.")
    if f'general/ios/app_id="{IOS_APP_ID}"' not in project_text:
        fail("project.godot no longer has ReefRun's iOS AdMob app id.")
    if 'const ANDROID_MODE := "test"' not in mode_text:
        fail("ANDROID_MODE must stay on Google's test unit.")
    if PRODUCTION_MODE not in mode_text or PRODUCTION_MARKER not in mode_text:
        fail(
            "IOS_MODE is not production. The committed source must stay on the "
            "live unit. Refusing to treat another mode as this diagnostic."
        )
    if mode_text.count(PRODUCTION_MODE) != 1 or mode_text.count(PRODUCTION_MARKER) != 1:
        fail("Expected exactly one iOS mode and one iOS output marker.")
    rewritten = mode_text.replace(PRODUCTION_MODE, DIAGNOSTIC_MODE, 1).replace(PRODUCTION_MARKER, DIAGNOSTIC_MARKER, 1)
    print(f"Diagnostic iOS mode selects {DEMO_UNIT}.")
    print(f"Production unit {PRODUCTION_UNIT} remains in ad_config.gd and is not requested.")
    print(f"iOS AdMob app id stays {IOS_APP_ID}.")
    print("This checkout is for internal TestFlight only. Do not commit it or submit it for App Store release.")
    if args.dry_run:
        print("Dry run. No file was written.")
        return
    MODE_FILE.write_text(rewritten, encoding="utf-8", newline="\n")
    print(f"Wrote {MODE_FILE}.")


if __name__ == "__main__":
    main()

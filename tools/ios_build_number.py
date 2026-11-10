"""Choose a CFBundleVersion Apple has not already accepted.

The Godot iOS preset is the minimum build number. When App Store Connect
already has that number, or a newer one, the next upload uses one higher
than the highest uploaded build. Marketing version stays 1.0.0.
"""

import argparse
import base64
import json
import os
import pathlib
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


BUNDLE_ID = "com.lunarentertainment.reefrun"
MARKETING_VERSION = "1.0.0"
ASC_API = "https://api.appstoreconnect.apple.com"
VERSION_LINE = re.compile(r'(?m)^(application/version=")(\d+)(")\s*$')
SHORT_LINE = re.compile(r'(?m)^application/short_version="([^"]+)"\s*$')


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def choose_build(preset: int, highest_uploaded: int) -> int:
    if preset < 1:
        fail(f"iOS build number {preset} is not a positive integer.")
    if highest_uploaded < 0:
        fail(f"Highest uploaded build {highest_uploaded} is not valid.")
    if preset > highest_uploaded:
        return preset
    return highest_uploaded + 1


def read_preset(path: pathlib.Path) -> tuple[str, int]:
    text = path.read_text(encoding="utf-8")
    short = SHORT_LINE.search(text)
    version = VERSION_LINE.search(text)
    if short is None or version is None:
        fail(f"{path} is missing the iOS marketing version or build number.")
    if short.group(1) != MARKETING_VERSION:
        fail(f"iOS marketing version must stay {MARKETING_VERSION}, found {short.group(1)}.")
    if len(VERSION_LINE.findall(text)) != 1:
        fail(f"{path} must contain one application/version build number.")
    return text, int(version.group(2))


def write_preset(path: pathlib.Path, text: str, build: int) -> None:
    updated, count = VERSION_LINE.subn(rf"\g<1>{build}\g<3>", text, count=1)
    if count != 1:
        fail(f"Could not write iOS build number {build} into {path}.")
    path.write_text(updated, encoding="utf-8", newline="\n")


def _b64url(data: bytes) -> bytes:
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def _der_to_raw(der: bytes) -> bytes:
    if len(der) < 8 or der[0] != 0x30:
        fail("App Store Connect signature was not an ECDSA sequence.")
    index = 2
    if der[1] & 0x80:
        index = 2 + (der[1] & 0x7F)

    def read_int(start: int) -> tuple[bytes, int]:
        if start >= len(der) or der[start] != 0x02:
            fail("App Store Connect signature was missing an integer.")
        length = der[start + 1]
        value = der[start + 2 : start + 2 + length]
        if len(value) > 32:
            value = value[-32:]
        return value.rjust(32, b"\x00"), start + 2 + length

    first, index = read_int(index)
    second, _index = read_int(index)
    return first + second


def app_store_token(key_id: str, issuer_id: str, private_key: pathlib.Path) -> str:
    now = int(time.time())
    header = _b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}, separators=(",", ":")).encode())
    payload = _b64url(
        json.dumps(
            {"iss": issuer_id, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
            separators=(",", ":"),
        ).encode()
    )
    signing_input = header + b"." + payload
    try:
        der = subprocess.check_output(
            ["openssl", "dgst", "-sha256", "-sign", str(private_key)],
            input=signing_input,
            stderr=subprocess.PIPE,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        detail = getattr(error, "stderr", b"")
        fail(f"Could not sign the App Store Connect token. {detail.decode('utf-8', errors='replace').strip()}")
    return (signing_input + b"." + _b64url(_der_to_raw(der))).decode("ascii")


def _get_json(url: str, token: str) -> dict:
    request = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        fail(f"App Store Connect returned HTTP {error.code} for {urllib.parse.urlparse(url).path}. {body[:500]}")
    except urllib.error.URLError as error:
        fail(f"Could not reach App Store Connect. {error.reason}")


def highest_uploaded_build(token: str, bundle_id: str) -> int:
    apps = _get_json(f"{ASC_API}/v1/apps?filter[bundleId]={urllib.parse.quote(bundle_id)}&limit=2", token)
    data = apps.get("data") or []
    if len(data) != 1:
        fail(f"App Store Connect returned {len(data)} apps for {bundle_id}.")
    app_id = str(data[0].get("id") or "")
    if not app_id:
        fail("App Store Connect did not return an app id.")
    highest = 0
    url = f"{ASC_API}/v1/builds?filter[app]={urllib.parse.quote(app_id)}&fields[builds]=version&limit=200"
    for _page in range(20):
        payload = _get_json(url, token)
        for item in payload.get("data") or []:
            version = str((item.get("attributes") or {}).get("version") or "").strip()
            if not version.isdecimal():
                fail(f"App Store Connect build version {version!r} is not an integer.")
            highest = max(highest, int(version))
        url = str((payload.get("links") or {}).get("next") or "")
        if not url:
            return highest
    fail("App Store Connect build list did not end.")


def resolve(preset_path: pathlib.Path, floor: int, app_store_highest: int | None) -> int:
    text, preset = read_preset(preset_path)
    uploaded = floor if app_store_highest is None else max(floor, app_store_highest)
    chosen = choose_build(preset, uploaded)
    if chosen != preset:
        write_preset(preset_path, text, chosen)
        print(f"Godot preset build {preset} is already on App Store Connect. Using {chosen}.")
    else:
        print(f"iOS build number is {chosen}. Highest uploaded build is {uploaded}.")
    return chosen


def self_test() -> None:
    if choose_build(11, 10) != 11:
        fail("preset 11 should stay ahead of uploaded build 10")
    if choose_build(11, 11) != 12 or choose_build(10, 10) != 11 or choose_build(11, 15) != 16:
        fail("a used build number must move to one above the highest upload")
    sample = 'application/short_version="1.0.0"\napplication/version="11"\n'
    path = pathlib.Path(os.environ.get("TEMP", ".")) / "reefrun-ios-build-self-test.cfg"
    path.write_text(sample, encoding="utf-8")
    try:
        chosen = resolve(path, 11, 11)
        written = path.read_text(encoding="utf-8")
    finally:
        path.unlink(missing_ok=True)
    if chosen != 12 or 'application/version="12"' not in written or 'application/short_version="1.0.0"' not in written:
        fail("resolve did not keep marketing version 1.0.0 while raising the build number")
    print("ios build number self-test passed")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--preset", type=pathlib.Path)
    parser.add_argument("--floor", type=int, default=0)
    parser.add_argument("--bundle-id", default=BUNDLE_ID)
    parser.add_argument("--key-id", default="")
    parser.add_argument("--issuer-id", default="")
    parser.add_argument("--private-key", type=pathlib.Path)
    parser.add_argument("--require-app-store", action="store_true")
    parser.add_argument("--github-env", type=pathlib.Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if args.preset is None:
        fail("Pass --preset export_presets.cfg.")
    highest = None
    if args.require_app_store:
        if not args.key_id or not args.issuer_id or args.private_key is None:
            fail("TestFlight upload needs the App Store Connect API key id, issuer id, and private key.")
        token = app_store_token(args.key_id, args.issuer_id, args.private_key)
        highest = highest_uploaded_build(token, args.bundle_id)
        print(f"App Store Connect highest CFBundleVersion is {highest}.")
    elif args.floor < 0:
        fail("The uploaded-build floor must be zero or higher.")
    chosen = resolve(args.preset, args.floor, highest)
    uploaded = args.floor if highest is None else max(args.floor, highest)
    if args.github_env is not None:
        with args.github_env.open("a", encoding="utf-8") as handle:
            handle.write(f"LAST_UPLOADED_IOS_BUILD={uploaded}\n")
            handle.write(f"IOS_BUILD_NUMBER={chosen}\n")
    print(f"NEXT_IOS_BUILD={chosen}")
    print(f"IOS_UPLOADED_FLOOR={uploaded}")


if __name__ == "__main__":
    main()

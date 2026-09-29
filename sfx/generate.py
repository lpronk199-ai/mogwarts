#!/usr/bin/env python3
"""Generate the Mogwarts sound effects from prompts.json with the ElevenLabs
Sound Effects API.

    export ELEVENLABS_API_KEY=...
    python3 sfx/generate.py                   # everything that is still missing
    python3 sfx/generate.py fire ice_cast     # only a category and/or a single sound
    python3 sfx/generate.py --force heal      # regenerate even if the file exists
    python3 sfx/generate.py --dry-run         # show what would be sent, call nothing

Sounds with "variants": N in prompts.json are requested N times (<id>_1.mp3 ... <id>_N.mp3).

Files land in assets/sfx/<category>/<id>.mp3. Uses only the standard library.
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

API_URL = "https://api.elevenlabs.io/v1/sound-generation"
ROOT = Path(__file__).resolve().parent.parent
MANIFEST = Path(__file__).resolve().parent / "prompts.json"
OUT_DIR = ROOT / "assets" / "sfx"
RETRY_STATUSES = {429, 500, 502, 503, 504}


def load_sounds(manifest):
    for category in manifest["categories"]:
        for sound in category["sounds"]:
            yield category["id"], sound


def build_request(manifest, sound, influence):
    defaults = manifest["defaults"]
    body = {
        "text": sound["prompt"] + manifest["suffix"],
        "model_id": defaults["model_id"],
        "prompt_influence": influence if influence is not None else defaults["prompt_influence"],
    }
    if sound.get("loop"):
        body["loop"] = True
    if "duration" in sound:
        body["duration_seconds"] = sound["duration"]
    return body


def generate(api_key, output_format, body, attempts=4):
    url = f"{API_URL}?output_format={output_format}"
    data = json.dumps(body).encode("utf-8")
    for attempt in range(attempts):
        req = urllib.request.Request(
            url,
            data=data,
            method="POST",
            headers={"xi-api-key": api_key, "Content-Type": "application/json", "Accept": "audio/mpeg"},
        )
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                return resp.read()
        except urllib.error.HTTPError as err:
            detail = err.read().decode("utf-8", "replace")[:300]
            if err.code in RETRY_STATUSES and attempt < attempts - 1:
                time.sleep(2 ** (attempt + 1))
                continue
            raise RuntimeError(f"HTTP {err.code}: {detail}") from None
        except urllib.error.URLError as err:
            if attempt < attempts - 1:
                time.sleep(2 ** (attempt + 1))
                continue
            raise RuntimeError(f"network error: {err.reason}") from None


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("only", nargs="*", help="category ids and/or sound ids to generate (default: all)")
    parser.add_argument("--force", action="store_true", help="overwrite files that already exist")
    parser.add_argument("--dry-run", action="store_true", help="print the requests without calling the API")
    parser.add_argument("--influence", type=float, help="prompt_influence 0-1, overrides prompts.json")
    parser.add_argument("--list", action="store_true", help="list all category and sound ids")
    args = parser.parse_args()

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    sounds = list(load_sounds(manifest))

    if args.list:
        for category, sound in sounds:
            kind = "loop" if sound.get("loop") else f"{sound['duration']}s"
            print(f"{category:18} {sound['id']:24} {kind}")
        return 0

    known = {c for c, _ in sounds} | {s["id"] for _, s in sounds}
    unknown = [name for name in args.only if name not in known]
    if unknown:
        parser.error(f"unknown id(s): {', '.join(unknown)} (see --list)")
    if args.only:
        sounds = [(c, s) for c, s in sounds if c in args.only or s["id"] in args.only]

    api_key = os.environ.get("ELEVENLABS_API_KEY")
    if not api_key and not args.dry_run:
        print("Set ELEVENLABS_API_KEY first (https://elevenlabs.io/app/settings/api-keys).", file=sys.stderr)
        return 1

    output_format = manifest["defaults"]["output_format"]
    done = skipped = failed = 0
    for category, sound in sounds:
        count = sound.get("variants", 1)
        names = [sound["id"]] if count == 1 else [f"{sound['id']}_{k}" for k in range(1, count + 1)]
        for name in names:
            target = OUT_DIR / category / f"{name}.mp3"
            rel = target.relative_to(ROOT)
            if target.exists() and not args.force:
                skipped += 1
                continue
            body = build_request(manifest, sound, args.influence)
            if args.dry_run:
                print(f"{rel}\n  {json.dumps(body, ensure_ascii=False)}")
                continue
            print(f"-> {rel} ...", end=" ", flush=True)
            try:
                audio = generate(api_key, output_format, body)
            except RuntimeError as err:
                print(f"FAILED ({err})")
                failed += 1
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(audio)
            print(f"ok ({len(audio) // 1024} KB)")
            done += 1

    if not args.dry_run:
        print(f"\n{done} generated, {skipped} already present, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

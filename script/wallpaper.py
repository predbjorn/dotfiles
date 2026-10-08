"""Firewatch-style wallpaper rotation.

Weekly: generate a new landscape with Gemini, rendered in four palettes
(dawn, day, golden, night) sharing one composition.
Daily: pick one landscape set at random from the library and keep it all day.
Through the day: show the palette matching Oslo's sun position.

Run every 10 minutes by launchd (.config/launchd/com.predbjorn.wallpaper.plist).

  wallpaper.py              generate if this week's set is missing, then apply
  wallpaper.py --generate   force a new set now
  wallpaper.py --reroll     pick a different set for today
"""

import argparse
import datetime
import fcntl
import json
import os
import random
import shutil
import subprocess
import sys
from io import BytesIO
from pathlib import Path

from astral import LocationInfo
from astral.sun import sun
from dotenv import load_dotenv
from PIL import Image

# Watch spending: https://console.cloud.google.com/billing/01B85F-1A6511-809A4F?project=gen-lang-client-0292679403&authuser=1
MODEL = "gemini-3-pro-image"
OSLO = LocationInfo("Oslo", "Norway", "Europe/Oslo", 59.9139, 10.7522)
LIBRARY = Path.home() / "Pictures/wallpaperscript/sets"
STATE_FILE = LIBRARY.parent / "state.json"
LOCK_FILE = LIBRARY.parent / ".wallpaper.lock"
PHASES = ["dawn", "day", "golden", "night"]
RETRY_AFTER = datetime.timedelta(hours=1)

load_dotenv(Path(__file__).resolve().parents[1] / ".env")
load_dotenv(Path.home() / ".dotfiles/.env")

BASE_PROMPT = (
    "Generate a single image only, no text response. "
    "A wide 21:9 ultrawide desktop wallpaper in the style of the Firewatch video game key art and Olly Moss's "
    "Firewatch posters: a richly detailed, layered vector landscape of the Wyoming wilderness. "
    "Deep parallax with 12 to 15 distinct depth layers receding into the distance. "
    "Far back: tall mountain ranges with sharp faceted peaks, each mountain shaded with flat light and shadow facets. "
    "Middle: many overlapping ridges blanketed in dense pine forest, every forest layer made of hundreds of individual "
    "jagged, pointed pine and spruce silhouettes along its edge, with soft bands of atmospheric haze and mist "
    "between the layers so each layer separates from the next. {feature} "
    "Foreground: large, detailed near-black pine trees with visible branch tiers framing the left and right edges, "
    "and a rocky ridge with grass and scattered boulders along the bottom. "
    "Sky: a smooth vertical gradient with a large glowing sun low over the ridges, gentle radiating light, "
    "a few long thin layered clouds, and a loose flock of small birds. "
    "Shapes are clean vector silhouettes with crisp edges and no outlines; colour comes from a strong single-hue "
    "analogous palette that shifts from light and hazy in the distance to dark and saturated up close. "
    "Dramatic, cinematic, quiet and lonely mood. High detail, intricate tree lines, poster quality. "
    "No people, no text, no logo, no title. "
    "Full-bleed artwork reaching every edge: no borders, no frame, no margins.\n\n"
    "Palette: {palette}"
)

RECOLOUR_PROMPT = (
    "Generate a single image only, no text response. "
    "Recolour this exact illustration for a different time of day. Keep the composition, every shape, "
    "every tree, every layer and the level of detail identical; only change the colours and lighting. {extra}\n\n"
    "Palette: {palette}"
)

# The lookout tower is the Firewatch signature, so it appears in most scenes.
FEATURES = [
    "On a rocky outcrop in the near-middle ground stands a tall wooden fire lookout tower on a lattice of stilts "
    "with a small cabin on top, drawn as a detailed silhouette.",
    "On a high ridge to one side stands a wooden fire lookout tower with a cabin on top, small against the mountains, "
    "with a winding trail leading up to it.",
    "A fire lookout tower stands on a hilltop above a still mountain lake that mirrors the forest and sky.",
    "A winding river glints through the valley floor between the forested ridges, with a distant lookout tower "
    "on a far hill.",
    "The ridges open into a deep canyon with layered faceted rock walls, a lookout tower perched on the rim.",
    "A wide open alpine meadow stretches across the middle distance, with a lone lookout tower beyond it.",
]

# Each phase follows one of the classic Firewatch colourways.
PALETTES = {
    "dawn": "soft rose-pink: sky pale peach #fbd9c4 near the horizon rising to pink #f4b8b0; pale sun #fff0e0; "
            "far ridges dusty rose #e6a6a4; mid ridges coral #d0706f; forests crimson #a3324a; "
            "foreground deep maroon #4a1028.",
    "day": "warm amber and gold: sky bright amber #f6a623 at the top fading to pale yellow #fcd977 at the horizon; "
           "sun cream #fff4c2; far ridges soft orange #f0a04a; mid ridges burnt orange #d0621f; "
           "forests rust #93321a; foreground dark brown-red #3a0d06.",
    "golden": "fiery red-orange sunset: sky orange #f26b2a at the top to warm yellow-orange #fbb04b at the horizon; "
              "sun glowing yellow #ffe08a; far ridges salmon red #e8603a; mid ridges red #c42a2a; "
              "forests deep crimson #7d1024; foreground near-black burgundy #2a0610.",
    "night": "deep blue and violet night: sky navy #0b1a4a at the top to royal blue #2a4fa8, with a magenta-pink glow "
             "#d24a8a along the horizon behind the mountains; far ridges violet #6a3aa8; mid ridges indigo #3a2a7a; "
             "forests dark purple #241a4a; foreground near-black #0a0a1e.",
}

PHASE_EXTRA = {
    "dawn": "Early morning: the sun is just rising, soft and pale, with gentle mist in the valleys.",
    "day": "",
    "golden": "Late evening: the sun is low and blazing over the ridges.",
    "night": "Replace the sun with a pale moon and add many small stars; the lookout tower cabin has one small "
             "warm lit window if a tower is present. Birds become a few distant silhouettes or are removed.",
}


# --- state -------------------------------------------------------------------

def load_state():
    try:
        return json.loads(STATE_FILE.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def save_state(state):
    STATE_FILE.write_text(json.dumps(state, indent=2))


def week_key(date):
    year, week, _ = date.isocalendar()
    return f"{year}-W{week:02d}"


def complete_sets():
    if not LIBRARY.exists():
        return []
    return sorted(
        p.name for p in LIBRARY.iterdir()
        if p.is_dir() and all((p / f"{phase}.png").exists() for phase in PHASES)
    )


# --- generation --------------------------------------------------------------

def _generate_image(client, contents):
    from google.genai import types

    response = client.models.generate_content(
        model=MODEL,
        contents=contents,
        config=types.GenerateContentConfig(
            response_modalities=["IMAGE"],
            image_config=types.ImageConfig(aspect_ratio="21:9", image_size="4K"),
        ),
    )
    for part in response.candidates[0].content.parts:
        if part.inline_data is not None and part.inline_data.data is not None:
            return Image.open(BytesIO(part.inline_data.data)).convert("RGB")
    raise RuntimeError(f"No image in Gemini response: {response.text!r}")


def generate_set(key):
    from google import genai

    client = genai.Client(api_key=os.getenv("GEMINI_API_KEY"))
    feature = random.choice(FEATURES)
    tmp = LIBRARY / f".{key}.tmp"
    shutil.rmtree(tmp, ignore_errors=True)
    tmp.mkdir(parents=True)

    print(f"Generating {key}: {feature}")
    base = _generate_image(client, BASE_PROMPT.format(feature=feature, palette=PALETTES["day"]))
    base.save(tmp / "day.png")
    for phase in ["dawn", "golden", "night"]:
        print(f"  recolouring {phase}")
        prompt = RECOLOUR_PROMPT.format(extra=PHASE_EXTRA[phase], palette=PALETTES[phase])
        _generate_image(client, [prompt, base]).save(tmp / f"{phase}.png")

    (tmp / "meta.json").write_text(json.dumps({
        "created": datetime.date.today().isoformat(),
        "model": MODEL,
        "feature": feature,
    }, indent=2))
    final = LIBRARY / key
    shutil.rmtree(final, ignore_errors=True)
    tmp.rename(final)


def ensure_this_week(state, force=False):
    key = week_key(datetime.date.today())
    if not force and key in complete_sets():
        return
    last = state.get("last_attempt")
    now = datetime.datetime.now()
    if not force and last and now - datetime.datetime.fromisoformat(last) < RETRY_AFTER:
        return
    state["last_attempt"] = now.isoformat(timespec="seconds")
    save_state(state)
    try:
        generate_set(key)
    except Exception as e:  # keep rotating existing sets if generation fails
        print(f"Generation failed: {e}", file=sys.stderr)
        if force:
            raise


# --- daily pick & phase ------------------------------------------------------

def _seeded_choice(date, options):
    return random.Random(date.isoformat()).choice(options) if options else None


def pick_set(date, state):
    sets = complete_sets()
    if not sets:
        return None
    override = state.get("overrides", {}).get(date.isoformat())
    if override in sets:
        return override
    for key in sets:  # a set generated today gets shown first
        meta = LIBRARY / key / "meta.json"
        if meta.exists() and json.loads(meta.read_text()).get("created") == date.isoformat():
            return key
    yesterday = _seeded_choice(date - datetime.timedelta(days=1), sets)
    return _seeded_choice(date, [s for s in sets if s != yesterday] or sets)


def current_phase(now):
    s = sun(OSLO.observer, date=now.date(), tzinfo=OSLO.timezone)
    sunrise, sunset = s["sunrise"], s["sunset"]
    # Around midsummer Oslo barely leaves civil twilight and astral wraps
    # dawn/dusk to the wrong side of sunrise/sunset.
    dawn = s["dawn"] if s["dawn"] < sunrise else sunrise - datetime.timedelta(minutes=45)
    dusk = s["dusk"] if s["dusk"] > sunset else sunset + datetime.timedelta(minutes=45)
    if now < dawn or now >= dusk:
        return "night"
    if now < sunrise + datetime.timedelta(hours=1):
        return "dawn"
    if now < sunset - datetime.timedelta(hours=1, minutes=30):
        return "day"
    return "golden"


# --- displays ----------------------------------------------------------------

JXA_SCREENS = """
ObjC.import('AppKit');
JSON.stringify(ObjC.unwrap($.NSScreen.screens).map(s => ({
  x: s.frame.origin.x, w: s.frame.size.width, h: s.frame.size.height, k: s.backingScaleFactor
})));
"""

JXA_SET = """
ObjC.import('AppKit');
const paths = JSON.parse('%s');
const screens = ObjC.unwrap($.NSScreen.screens);
paths.forEach((p, i) => {
  $.NSWorkspace.sharedWorkspace.setDesktopImageURLForScreenOptionsError(
    $.NSURL.fileURLWithPath(p), screens[i], $({}), null);
});
"""


def _jxa(script):
    out = subprocess.run(["osascript", "-l", "JavaScript", "-e", script],
                         check=True, capture_output=True, text=True)
    return out.stdout.strip()


def screens():
    return json.loads(_jxa(JXA_SCREENS))


def crop_for(master_path, width, height, align):
    """Scale-and-crop the 4K master to a display; align is 0 (left) .. 1 (right)."""
    out = master_path.with_name(f"{master_path.stem}_{width}x{height}.png")
    if out.exists():
        return out
    img = Image.open(master_path)
    scale = max(width / img.width, height / img.height)
    img = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    left = round((img.width - width) * align)
    top = (img.height - height) // 2
    img.crop((left, top, left + width, top + height)).save(out)
    return out


def apply(set_key, phase):
    master = LIBRARY / set_key / f"{phase}.png"
    displays = screens()
    main_x = displays[0]["x"]  # NSScreen.screens[0] is the main display
    paths = []
    for d in displays:
        align = 0.5 if d["x"] == main_x else (0.0 if d["x"] < main_x else 1.0)
        paths.append(str(crop_for(master, round(d["w"] * d["k"]), round(d["h"] * d["k"]), align)))
    _jxa(JXA_SET % json.dumps(paths))
    return paths


# --- main --------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--generate", action="store_true", help="force a new landscape set now")
    parser.add_argument("--reroll", action="store_true", help="pick a different set for today")
    args = parser.parse_args()

    LIBRARY.mkdir(parents=True, exist_ok=True)
    with open(LOCK_FILE, "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("Another wallpaper run is in progress")
            return

        state = load_state()
        ensure_this_week(state, force=args.generate)

        today = datetime.date.today()
        if args.reroll:
            current = pick_set(today, state)
            others = [s for s in complete_sets() if s != current]
            if others:
                overrides = {k: v for k, v in state.get("overrides", {}).items() if k >= today.isoformat()}
                overrides[today.isoformat()] = random.choice(others)
                state["overrides"] = overrides

        set_key = pick_set(today, state)
        if set_key is None:
            print("No landscape sets yet", file=sys.stderr)
            save_state(state)
            return
        phase = current_phase(datetime.datetime.now(datetime.timezone.utc).astimezone())
        signature = f"{today.isoformat()}/{set_key}/{phase}/{len(screens())}"
        if signature != state.get("applied") or args.reroll or args.generate:
            paths = apply(set_key, phase)
            state["applied"] = signature
            print(f"Wallpaper: {set_key} {phase} -> {paths}")
        save_state(state)


if __name__ == "__main__":
    main()

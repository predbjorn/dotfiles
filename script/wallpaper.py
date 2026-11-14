"""Firewatch-style wallpaper rotation.

Weekly: generate a new landscape with Gemini, rendered in four palettes
(dawn, day, golden, night) sharing one composition.
Daily: pick one landscape set at random from the library and keep it all day.
Through the day: cross-fade between the palettes following Oslo's sun, so the
desktop drifts night -> dawn -> day -> golden -> night instead of jumping.
Also writes ~/Pictures/wallpaperscript/live/, a self-contained page that animates
the same blend with clouds, mist, birds and stars (shown on the desktop by Plash).

Run every 5 minutes by launchd (.config/launchd/com.predbjorn.wallpaper.plist).

  wallpaper.py              generate if this week's set is missing, then apply
  wallpaper.py --generate   force a new set now
  wallpaper.py --reroll     pick a different set for today
  wallpaper.py --at 07:30   show the blend for that time today (preview; changes nothing saved)
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
from astral.sun import dawn as nautical_dawn, dusk as nautical_dusk, sun
from dotenv import load_dotenv
from PIL import Image

# Watch spending: https://console.cloud.google.com/billing/01B85F-1A6511-809A4F?project=gen-lang-client-0292679403&authuser=1
MODEL = "gemini-3-pro-image"
OSLO = LocationInfo("Oslo", "Norway", "Europe/Oslo", 59.9139, 10.7522)
LIBRARY = Path.home() / "Pictures/wallpaperscript/sets"
STATE_FILE = LIBRARY.parent / "state.json"
LOCK_FILE = LIBRARY.parent / ".wallpaper.lock"
CURRENT_DIR = LIBRARY.parent / "current"  # blended per-display wallpapers
LIVE_DIR = LIBRARY.parent / "live"  # page + state for the animated desktop
LIVE_PAGE = Path(__file__).resolve().parent / "live-wallpaper/index.html"
BLEND_STEPS = 20  # blend factor resolution; caps how many distinct wallpapers a fade makes
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


def _sun_times(date):
    s = sun(OSLO.observer, date=date, tzinfo=OSLO.timezone)
    sunrise, sunset = s["sunrise"], s["sunset"]
    try:  # around midsummer Oslo never gets 12 degrees below the horizon
        first = nautical_dawn(OSLO.observer, date=date, tzinfo=OSLO.timezone, depression=12)
        last = nautical_dusk(OSLO.observer, date=date, tzinfo=OSLO.timezone, depression=12)
    except ValueError:
        first = last = None
    if first is None or not first < sunrise:
        first = sunrise - datetime.timedelta(minutes=90)
    if last is None or not last > sunset:
        last = sunset + datetime.timedelta(minutes=90)
    return first, sunrise, sunset, last


def anchors(date):
    """(time, phase) keyframes for one day; the wallpaper fades between neighbours."""
    first, sunrise, sunset, last = _sun_times(date)
    h = datetime.timedelta(hours=1)
    noon = sunrise + (sunset - sunrise) / 2
    keys = [
        (first, "night"),
        (sunrise, "dawn"),
        (min(sunrise + h, noon), "dawn"),
        (min(sunrise + 2 * h, noon), "day"),
        (max(sunset - 2.5 * h, noon), "day"),
        (max(sunset - h, noon), "golden"),
        (sunset + datetime.timedelta(minutes=20), "golden"),
        (last, "night"),
    ]
    out = []
    for t, phase in keys:  # keep times monotonic when the day is short
        out.append((max(t, out[-1][0]) if out else t, phase))
    return out


def blend_at(now):
    """(from_phase, to_phase, t) where t in 0..1 is how far the fade has gone."""
    # Yesterday too: around midsummer the evening fade runs past midnight.
    for keys in (anchors(now.date() - datetime.timedelta(days=1)), anchors(now.date())):
        for (t0, a), (t1, b) in zip(keys, keys[1:]):
            if t0 <= now < t1:
                if a == b:
                    return a, a, 0.0
                x = (now - t0) / (t1 - t0)
                return a, b, x * x * (3 - 2 * x)  # smoothstep: ease in and out of each fade
    return "night", "night", 0.0


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
    # The master's mtime is part of the name: macOS caches wallpapers by path, so a
    # regenerated set must not reuse the old file names.
    stamp = int(master_path.stat().st_mtime)
    out = master_path.with_name(f"{master_path.stem}_{width}x{height}_{stamp}.png")
    if out.exists():
        return out
    for stale in master_path.parent.glob(f"{master_path.stem}_{width}x{height}*.png"):
        stale.unlink()
    img = Image.open(master_path)
    scale = max(width / img.width, height / img.height)
    img = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    left = round((img.width - width) * align)
    top = (img.height - height) // 2
    img.crop((left, top, left + width, top + height)).save(out)
    return out


def _display_crops(set_key, phase, displays):
    master = LIBRARY / set_key / f"{phase}.png"
    main_x = displays[0]["x"]  # NSScreen.screens[0] is the main display
    out = []
    for d in displays:
        align = 0.5 if d["x"] == main_x else (0.0 if d["x"] < main_x else 1.0)
        out.append(crop_for(master, round(d["w"] * d["k"]), round(d["h"] * d["k"]), align))
    return out


def apply(set_key, a, b, t, displays):
    """Blend phases a -> b by t for every display and set them as the wallpaper."""
    CURRENT_DIR.mkdir(exist_ok=True)
    tag = f"{set_key}_{a}-{b}-{t:.2f}_{datetime.datetime.now():%H%M%S}"
    paths = []
    for i, (pa, pb) in enumerate(zip(_display_crops(set_key, a, displays), _display_crops(set_key, b, displays))):
        if t == 0:
            paths.append(pa)
            continue
        out = CURRENT_DIR / f"{i}_{tag}.png"
        Image.blend(Image.open(pa).convert("RGB"), Image.open(pb).convert("RGB"), t).save(out)
        paths.append(out)
    _jxa(JXA_SET % json.dumps([str(p) for p in paths]))
    for old in CURRENT_DIR.glob("*.png"):  # unique names per run: macOS caches wallpapers by path
        if old not in paths:
            old.unlink()
    return paths


# --- live page ---------------------------------------------------------------

def _small(path):
    import numpy as np

    img = Image.open(path).convert("RGB")
    return np.asarray(img.resize((480, round(480 * img.height / img.width))), dtype=np.float32)


def _phase_info(path):
    """Where the sun/moon sits (fractions of the image) and the sky colours, for the page's effects."""
    import numpy as np
    from scipy.ndimage import uniform_filter

    small = _small(path)
    h, w, _ = small.shape
    upper = small.mean(axis=2)[: int(h * 0.6)]
    soft = uniform_filter(upper, size=5)  # stars are single pixels; the sun/moon is a disc
    y, x = np.unravel_index(soft.argmax(), soft.shape)
    ys, xs = np.nonzero(upper > upper.max() - 12)
    near = (abs(ys - y) < h * 0.15) & (abs(xs - x) < w * 0.1)
    if near.any():
        x, y, radius = xs[near].mean(), ys[near].mean(), np.sqrt(near.sum() / np.pi)
    else:
        radius = w * 0.02
    top = small[: max(1, h // 20)].reshape(-1, 3).mean(axis=0)
    band = small[int(h * 0.45): int(h * 0.55)].reshape(-1, 3)
    haze = band[band.sum(axis=1).argsort()[-len(band) // 10:]].mean(axis=0)
    return {
        "sun": [round(float(x) / w, 4), round(float(y) / h, 4), round(float(radius) / w, 4)],
        "sky": [int(c) for c in top],
        "haze": [int(c) for c in haze],
    }


def _skyline(paths):
    """Per column (240 samples), the height where the mountains start, as a fraction from the top.

    The first strong colour step from the top. Night works best: the sky is dark against lit ridges,
    while at dawn pale peaks melt into the sky. Glows and clouds give false hits that sit too high and
    differ per image, so with several images the lowest hit is the real ridge.
    """
    import numpy as np
    from scipy.ndimage import median_filter, uniform_filter

    lines = []
    for path in paths:
        small = _small(path)
        h = small.shape[0]
        sm = uniform_filter(small, size=(7, 7, 1))
        step = np.abs(sm[4:] - sm[:-4]).sum(axis=2)[int(h * 0.05):]
        hit = step > 40
        first = np.where(hit.any(axis=0), hit.argmax(axis=0), int(h * 0.55)) + int(h * 0.05) + 2
        lines.append(first[::2] / h)
    ridge = median_filter(np.max(lines, axis=0), size=9, mode="nearest")
    return [round(float(v), 3) for v in ridge]


def write_live(set_key, display):
    """Mirror today's set into LIVE_DIR so the page (and Plash) only needs that folder."""
    LIVE_DIR.mkdir(exist_ok=True)
    width, height = round(display["w"] * display["k"]), round(display["h"] * display["k"])
    images, crops, keep = {}, {}, {"index.html", "state.js"}
    for phase in PHASES:
        crops[phase] = crop_for(LIBRARY / set_key / f"{phase}.png", width, height, 0.5)
        name = f"{set_key}_{crops[phase].name}"
        if not (LIVE_DIR / name).exists():
            os.link(crops[phase], LIVE_DIR / name)  # hard link: no extra disk
        images[phase] = name
        keep.add(name)
    info_file = LIBRARY / set_key / f"scene_{width}x{height}.json"
    if info_file.exists():
        info = json.loads(info_file.read_text())
    else:
        info = {phase: _phase_info(crops[phase]) for phase in PHASES}
        info["skyline"] = _skyline([crops["night"]])
        info_file.write_text(json.dumps(info))
    for old in LIVE_DIR.iterdir():
        if old.name not in keep:
            old.unlink()
    today = datetime.date.today()
    days = [today - datetime.timedelta(days=1), today, today + datetime.timedelta(days=1)]
    state = {
        "set": set_key,
        "images": images,
        "scene": info,
        "anchors": [[[int(t.timestamp() * 1000), phase] for t, phase in anchors(d)] for d in days],
    }
    (LIVE_DIR / "state.js").write_text(f"window.WALLPAPER = {json.dumps(state)};\n")
    page = LIVE_DIR / "index.html"
    if not page.exists() or page.read_bytes() != LIVE_PAGE.read_bytes():
        shutil.copyfile(LIVE_PAGE, page)


# --- main --------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--generate", action="store_true", help="force a new landscape set now")
    parser.add_argument("--reroll", action="store_true", help="pick a different set for today")
    parser.add_argument("--at", help="preview the blend at HH:MM today (not saved to state)")
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
        now = datetime.datetime.now(datetime.timezone.utc).astimezone()
        if args.at:
            hour, minute = map(int, args.at.split(":"))
            now = now.replace(hour=hour, minute=minute)
        a, b, t = blend_at(now)
        t = round(t * BLEND_STEPS) / BLEND_STEPS
        if t == 1:
            a, t = b, 0.0
        displays = screens()
        signature = f"{today.isoformat()}/{set_key}/{a}-{b}-{t:.2f}/{len(displays)}"
        if signature != state.get("applied") or args.reroll or args.generate or args.at:
            paths = apply(set_key, a, b, t, displays)
            print(f"Wallpaper: {set_key} {a}->{b} {t:.2f} -> {[str(p) for p in paths]}")
            if args.at:
                state.pop("applied", None)  # the next normal run puts the real blend back
                save_state(state)
                return
            state["applied"] = signature
        try:  # the live page is extra; never let it stop the still wallpaper
            write_live(set_key, displays[0])
        except Exception as e:
            print(f"Live page update failed: {e}", file=sys.stderr)
        save_state(state)


if __name__ == "__main__":
    main()

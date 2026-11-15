"""Firewatch-style wallpaper rotation.

Library: landscape sets made on demand with Gemini, each rendered in four palettes
(dawn, day, golden, night) sharing one composition, dressed for a season
(snow in winter, golden larches in autumn, ...) or for rain. Nothing is generated
automatically; the library is fixed and rotated.
Daily: pick one landscape set at random from the library and keep it all day,
preferring sets from the current season once there are a few. While it rains
(or snows) in Oslo, a rain (or snow) set takes over if the library has one.
Through the day: cross-fade between the palettes following Oslo's sun, so the
desktop drifts night -> dawn -> day -> golden -> night instead of jumping.
Also writes ~/Pictures/wallpaperscript/live/, a self-contained page that animates
the same blend with clouds, mist, birds and stars (shown on the desktop by Plash),
plus Oslo's current weather from MET Norway (yr.no): rain, snow, fog, overcast, wind.

Run every 5 minutes by launchd (.config/launchd/com.predbjorn.wallpaper.plist).

  wallpaper.py              apply the current blend
  wallpaper.py --generate   make a new set now (4 Gemini images), shown first today
  wallpaper.py --reroll     pick a different set for today
  wallpaper.py --at 07:30   show the blend for that time today (preview; changes nothing saved)
  wallpaper.py --convert 2026-W42 winter
                            make a winter (or spring/autumn/rain) copy of a set (4 Gemini images)
  wallpaper.py --show 2026-W42-rain
                            show that set for the rest of today
"""

import argparse
import datetime
import fcntl
import json
import math
import os
import random
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
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
WEATHER_FILE = LIBRARY.parent / "weather.json"
# MET Norway asks for a User-Agent naming the client; keep it generic.
WEATHER_URL = "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=59.91&lon=10.75"
WEATHER_AGENT = "dotfiles-wallpaper/1.0"
WEATHER_MAX_AGE = datetime.timedelta(minutes=30)

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


SEASON_OF_MONTH = {12: "winter", 1: "winter", 2: "winter", 3: "winter", 4: "spring", 5: "spring",
                   6: "summer", 7: "summer", 8: "summer", 9: "autumn", 10: "autumn", 11: "autumn"}

SEASON_SCENE = {
    "winter": "Deep winter: thick snow blankets the ground, the rocks and every pine branch, the peaks are "
              "snow-capped and any lake or river is frozen white.",
    "spring": "Late spring: fresh meadow grass and a few wildflowers, the last snow only on the highest peaks.",
    "summer": "",
    "autumn": "Autumn: golden larches and birches glow among the dark pines, and fallen leaves lie on the rocks.",
}

# Weather looks; falling rain and snow are left out because the live page animates them.
WEATHER_SCENE = {
    "rain": "A rainy day: a heavy grey cloud deck hides the sun and the birds, low clouds and drifting mist "
            "hang between the ridges and veil the peaks, the rocks and trail glisten wet with small puddles, "
            "and the colours are softer and greyer than before. Do not draw falling raindrops.",
}

CONVERT_PROMPT = (
    "Generate a single image only, no text response. "
    "Redraw this exact illustration in a different season. Keep the composition, every shape, every tree, "
    "every layer, the level of detail and the colour palette; only add what the season brings. "
    "Do not draw falling snow. {scene}"
)

WEATHER_CONVERT_PROMPT = (
    "Generate a single image only, no text response. "
    "Redraw this exact illustration in different weather. Keep the composition, every shape, every tree, "
    "every layer and the level of detail; only change what the weather brings. {scene}"
)

LOOKS = [*SEASON_SCENE, *WEATHER_SCENE]

# Recolouring otherwise brings back a blazing sun or washes the snow into the palette.
KEEP_LOOK = {
    "winter": "Keep all the snow: it takes on the colour of the light but stays clearly paler than the forests, "
              "so the scene still reads as deep winter.",
    "spring": "Keep the fresh grass and wildflowers.",
    "autumn": "Keep the golden larches and birches and the fallen leaves.",
    "rain": "Keep the rainy weather: the heavy cloud deck still hides the sun, the moon and the stars, "
            "with low clouds, mist and wet rocks; the light only tints the clouds.",
}
WEATHER_PHASE_EXTRA = {  # replaces PHASE_EXTRA for weather looks
    "dawn": "Early morning: a faint pale glow behind the clouds near the horizon.",
    "golden": "Late evening: a warm glow seeps through a break in the clouds along the horizon; no visible sun.",
    "night": "Night under a heavy cloud deck: no moon and no stars; the lookout tower cabin has one small warm "
             "lit window if a tower is present.",
}


def season_of(date):
    return SEASON_OF_MONTH[date.month]


# --- state -------------------------------------------------------------------

def load_state():
    try:
        return json.loads(STATE_FILE.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def save_state(state):
    STATE_FILE.write_text(json.dumps(state, indent=2))


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


def recolour(client, base, look, phase):
    print(f"  recolouring {phase}")
    extra = (WEATHER_PHASE_EXTRA if look in WEATHER_SCENE else PHASE_EXTRA)[phase]
    extra = f"{extra} {KEEP_LOOK.get(look, '')}".strip()
    return _generate_image(client, [RECOLOUR_PROMPT.format(extra=extra, palette=PALETTES[phase]), base])


def generate_set(key, look=None, source=None):
    """Make a set: a new landscape, or with source=<set key> a season/weather copy of an existing one."""
    from google import genai

    client = genai.Client(api_key=os.getenv("GEMINI_API_KEY"))
    look = look or season_of(datetime.date.today())
    tmp = LIBRARY / f".{key}.tmp"
    shutil.rmtree(tmp, ignore_errors=True)
    tmp.mkdir(parents=True)

    if source:
        feature = json.loads((LIBRARY / source / "meta.json").read_text()).get("feature", "")
        print(f"Converting {source} to {look} as {key}")
        prompt = (WEATHER_CONVERT_PROMPT.format(scene=WEATHER_SCENE[look]) if look in WEATHER_SCENE
                  else CONVERT_PROMPT.format(scene=SEASON_SCENE[look]))
        base = _generate_image(client, [prompt, Image.open(LIBRARY / source / "day.png")])
    else:
        feature = random.choice(FEATURES)
        print(f"Generating {key} ({look}): {feature}")
        scene = f"{feature} {SEASON_SCENE.get(look) or WEATHER_SCENE[look]}".strip()
        base = _generate_image(client, BASE_PROMPT.format(feature=scene, palette=PALETTES["day"]))
    base.save(tmp / "day.png")
    for phase in ["dawn", "golden", "night"]:
        recolour(client, base, look, phase).save(tmp / f"{phase}.png")

    (tmp / "meta.json").write_text(json.dumps({
        "created": datetime.date.today().isoformat(),
        "model": MODEL,
        "feature": feature,
        **({"weather": look} if look in WEATHER_SCENE else {"season": look}),
        **({"source": source} if source else {}),
    }, indent=2))
    final = LIBRARY / key
    shutil.rmtree(final, ignore_errors=True)
    tmp.rename(final)


# --- daily pick & phase ------------------------------------------------------

def _seeded_choice(date, options):
    return random.Random(date.isoformat()).choice(options) if options else None


def pick_set(date, state, wx=None):
    sets = complete_sets()
    if not sets:
        return None
    override = state.get("overrides", {}).get(date.isoformat())
    if override in sets:
        return override
    metas = {key: _meta(key) for key in sets}
    falling = (wx or {}).get("kind")
    if falling in ("rain", "sleet") or (wx or {}).get("thunder"):
        wet = [s for s in sets if metas[s].get("weather") == "rain"]
    elif falling == "snow":
        wet = [s for s in sets if metas[s].get("season") == "winter"]
    else:
        wet = []
    if wet:
        return _seeded_choice(date, wet)
    for key in sets:  # a set made today gets shown first
        if metas[key].get("created") == date.isoformat():
            return key
    return _seeded_pick(date, _season_pool(date, [s for s in sets if not metas[s].get("weather")], metas))


def _meta(key):
    try:
        return json.loads((LIBRARY / key / "meta.json").read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def _season_pool(date, sets, metas):
    """This season's sets once there are a couple; before that, everything but other seasons' snow."""
    season = season_of(date)
    matching = [s for s in sets if metas[s].get("season") == season]
    if len(matching) >= 2:
        return matching
    # Sets without snow fit any time of year; snowy ones only in winter.
    return [s for s in sets if season == "winter" or metas[s].get("season") != "winter"] or sets


def _seeded_pick(date, pool):
    yesterday = _seeded_choice(date - datetime.timedelta(days=1), pool)
    return _seeded_choice(date, [s for s in pool if s != yesterday] or pool)


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


def _fetch_forecast(cached):
    req = urllib.request.Request(WEATHER_URL, headers={"User-Agent": WEATHER_AGENT})
    if cached.get("last_modified"):
        req.add_header("If-Modified-Since", cached["last_modified"])
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return {"fetched": datetime.datetime.now().isoformat(timespec="seconds"),
                    "last_modified": resp.headers.get("Last-Modified"),
                    "forecast": json.load(resp)}
    except urllib.error.HTTPError as e:
        if e.code == 304:  # unchanged since last time
            return {**cached, "fetched": datetime.datetime.now().isoformat(timespec="seconds")}
        raise


def weather(now):
    """Oslo's weather for this hour from MET Norway, cached; None when unavailable."""
    try:
        cached = json.loads(WEATHER_FILE.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        cached = {}
    fetched = cached.get("fetched")
    if not fetched or datetime.datetime.now() - datetime.datetime.fromisoformat(fetched) > WEATHER_MAX_AGE:
        try:
            cached = _fetch_forecast(cached)
            WEATHER_FILE.write_text(json.dumps(cached))
        except Exception as e:  # offline: keep the last forecast if there is one
            print(f"Weather fetch failed: {e}", file=sys.stderr)
    series = cached.get("forecast", {}).get("properties", {}).get("timeseries", [])
    hour = now.astimezone(datetime.timezone.utc).replace(minute=0, second=0, microsecond=0)
    entry = next((e for e in series if datetime.datetime.fromisoformat(e["time"].replace("Z", "+00:00")) >= hour), None)
    if not entry:
        return None
    details = entry["data"]["instant"]["details"]
    nxt = entry["data"].get("next_1_hours", {})
    symbol = nxt.get("summary", {}).get("symbol_code", "")
    precip = nxt.get("details", {}).get("precipitation_amount", 0.0)
    temp = details.get("air_temperature", 5.0)
    kind = ("snow" if "snow" in symbol else "sleet" if "sleet" in symbol else "rain" if "rain" in symbol
            else None if precip < 0.1 else "snow" if temp <= 0 else "sleet" if temp <= 1.5 else "rain")
    strength = 0.3 if symbol.startswith("light") else 0.9 if symbol.startswith("heavy") else 0.55
    wind = details.get("wind_speed", 0.0)
    return {
        "symbol": symbol,
        "clouds": round(details.get("cloud_area_fraction", 30.0) / 100, 2),
        "fog": 1.0 if symbol.startswith("fog") else round(max(0.0, details.get("fog_area_fraction", 0.0)) / 100, 2),
        "kind": kind,
        "intensity": round(max(strength, min(precip / 4, 1.0)), 2) if kind else 0.0,
        "thunder": "thunder" in symbol,
        "wind": round(wind, 1),
        # East-west part of the wind (positive blows towards the right of a north-facing view).
        "wind_x": round(-math.sin(math.radians(details.get("wind_from_direction", 270.0))) * wind, 1),
        "temp": temp,
    }


def write_live(set_key, display, wx):
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
        "weather": wx,
        "look": _meta(set_key).get("weather") or _meta(set_key).get("season"),
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
    parser.add_argument("--convert", nargs=2, metavar=("SET", "LOOK"),
                        help=f"make a copy of a set in another look ({', '.join(LOOKS)}), shown first today")
    parser.add_argument("--show", metavar="SET", help="show this set for the rest of today")
    args = parser.parse_args()
    if args.convert and args.convert[1] not in LOOKS:
        parser.error(f"look must be one of {', '.join(LOOKS)}")

    LIBRARY.mkdir(parents=True, exist_ok=True)
    with open(LOCK_FILE, "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("Another wallpaper run is in progress")
            return

        state = load_state()
        if args.convert:
            source, look = args.convert
            generate_set(f"{source}-{look}", look=look, source=source)
        if args.generate:
            generate_set(datetime.datetime.now().strftime("%Y-%m-%d-%H%M"))

        today = datetime.date.today()
        wx = weather(datetime.datetime.now().astimezone())
        override = None
        if args.show:
            if args.show not in complete_sets():
                parser.error(f"no complete set {args.show!r}; have {', '.join(complete_sets())}")
            override = args.show
        elif args.reroll:
            current = pick_set(today, state, wx)
            others = [s for s in complete_sets() if s != current]
            override = random.choice(others) if others else None
        if override:
            overrides = {k: v for k, v in state.get("overrides", {}).items() if k >= today.isoformat()}
            overrides[today.isoformat()] = override
            state["overrides"] = overrides

        set_key = pick_set(today, state, wx)
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
        if signature != state.get("applied") or args.reroll or args.show or args.generate or args.at or args.convert:
            paths = apply(set_key, a, b, t, displays)
            print(f"Wallpaper: {set_key} {a}->{b} {t:.2f} -> {[str(p) for p in paths]}")
            if args.at:
                state.pop("applied", None)  # the next normal run puts the real blend back
                save_state(state)
                return
            state["applied"] = signature
        try:  # the live page is extra; never let it stop the still wallpaper
            write_live(set_key, displays[0], wx)
        except Exception as e:
            print(f"Live page update failed: {e}", file=sys.stderr)
        save_state(state)


if __name__ == "__main__":
    main()

"""Firewatch-style wallpaper rotation.

Library: landscape sets made on demand with Gemini, each rendered in four palettes
(dawn, day, golden, night) sharing one composition, dressed for a season
(snow in winter, golden larches in autumn, ...) or for rain. Nothing is generated
automatically; the library is fixed and rotated. It lives in the repo (wallpapers/, WebP),
so a new Mac gets every set with the dotfiles; crops and analysis are rebuilt in
~/Pictures/wallpaperscript/cache/.
Daily: pick one landscape set at random from the library and keep it all day,
preferring sets from the current season once there are a few. While it rains
(or snows) in Kristiansand, a rain (or snow) set takes over if the library has one.
Through the day: cross-fade between the palettes following Kristiansand's sun, so the
desktop drifts night -> dawn -> day -> golden -> night instead of jumping.
Also writes ~/Pictures/wallpaperscript/live/, a self-contained page that animates
the same blend with clouds, mist, birds and stars (shown on the desktop by Plash),
plus Kristiansand's current weather from MET Norway (yr.no): rain, snow, fog, overcast, wind,
and a forecast panel for the next hours and days.

Run every 5 minutes by launchd (.config/launchd/com.predbjorn.wallpaper.plist).

  wallpaper.py              apply the current blend
  wallpaper.py --generate [fjord]
                            make a new set now (4 Gemini images), shown first today; without a
                            terrain, one the library has fewest of
  wallpaper.py --reroll     pick a different set for today
  wallpaper.py --at 07:30   show the blend for that time today (preview; changes nothing saved)
  wallpaper.py --convert 2026-W42 winter
                            make a winter (or spring/autumn/rain) copy of a set (4 Gemini images)
  wallpaper.py --show 2026-W42-rain
                            show that set for the rest of today (--show auto: back to the daily pick)
  wallpaper.py --weather snow
                            use that weather on the live page for the rest of today, picking a
                            rain/snow set to match (--weather auto: the real weather again)
  wallpaper.py --status     print today's set, weather and the choices as JSON (for the sketchybar menu)
  wallpaper.py --gallery    build and open ~/Pictures/wallpaperscript/gallery/: click through every
                            set in any weather and time of day
"""

import argparse
import datetime
import fcntl
import json
import math
import os
import random
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
import zoneinfo
from io import BytesIO
from pathlib import Path

from astral import LocationInfo
from astral.sun import dawn as nautical_dawn, dusk as nautical_dusk, sun
from dotenv import dotenv_values, load_dotenv
from PIL import Image

# Watch spending: https://console.cloud.google.com/billing/01B85F-1A6511-809A4F?project=gen-lang-client-0292679403&authuser=1
MODEL = "gemini-3-pro-image"
# Where the sun times and the weather come from.
PLACE = LocationInfo("Kristiansand", "Norway", "Europe/Oslo", 58.1467, 7.9956)
# The sets live in the repo (wallpapers/<set>/{dawn,day,golden,night}.webp + meta.json + features.json),
# so a new Mac gets them with the dotfiles. Everything derived from them goes under WORK.
LIBRARY = Path(__file__).resolve().parents[1] / "wallpapers"
WORK = Path.home() / "Pictures/wallpaperscript"
CACHE = WORK / "cache"  # per set: screen-sized crops, scene analysis, effect masks
STATE_FILE = WORK / "state.json"
LOCK_FILE = WORK / ".wallpaper.lock"
CURRENT_DIR = WORK / "current"  # blended per-display wallpapers
LIVE_DIR = WORK / "live"  # page + state for the animated desktop
LIVE_PAGE = Path(__file__).resolve().parent / "live-wallpaper/index.html"
GALLERY_DIR = WORK / "gallery"  # click-through page of every set
GALLERY_PAGE = Path(__file__).resolve().parent / "live-wallpaper/gallery.html"
BLEND_STEPS = 20  # blend factor resolution; caps how many distinct wallpapers a fade makes
PHASES = ["dawn", "day", "golden", "night"]
WEATHER_FILE = WORK / "weather.json"
# MET Norway asks for a User-Agent naming the client; keep it generic.
# "complete" rather than "compact": it adds the chance of rain for the next hours. Same data as yr.no.
WEATHER_URL = (f"https://api.met.no/weatherapi/locationforecast/2.0/complete"
               f"?lat={PLACE.latitude:.2f}&lon={PLACE.longitude:.2f}")  # MET wants at most 4 decimals
WEATHER_AGENT = "dotfiles-wallpaper/1.0"
WEATHER_MAX_AGE = datetime.timedelta(minutes=30)
# Weather presets the live page knows (WEATHER_PRESETS in live-wallpaper/index.html), with
# what pick_set needs to swap in a rain or snow set.
WEATHER_PRESETS = {
    "clear": {}, "overcast": {}, "fog": {}, "windy": {}, "aurora": {},
    "rain": {"kind": "rain"}, "sleet": {"kind": "sleet"}, "snow": {"kind": "snow"},
    "blizzard": {"kind": "snow"}, "thunder": {"kind": "rain", "thunder": True},
    "storm": {"kind": "rain", "thunder": True},
}

load_dotenv(Path(__file__).resolve().parents[1] / ".env")
load_dotenv(Path.home() / ".dotfiles/.env")

BASE_PROMPT = (
    "Generate a single image only, no text response. "
    "A wide 21:9 ultrawide desktop wallpaper in the style of the Firewatch video game key art and Olly Moss's "
    "Firewatch posters: a richly detailed, layered vector landscape. "
    "Deep parallax with 10 to 15 distinct depth layers receding into the distance, each shaded with flat light "
    "and shadow facets, with soft bands of atmospheric haze and mist between the layers so each layer separates "
    "from the next. Scene: {feature} "
    "Sky: a smooth vertical gradient with a large glowing sun low in the sky, gentle radiating light, "
    "a few long thin layered clouds, and a loose flock of small birds. "
    "Shapes are clean vector silhouettes with crisp edges and no outlines; colour comes from a strong single-hue "
    "analogous palette that shifts from light and hazy in the distance to dark and saturated up close. "
    "Dramatic, cinematic, quiet and lonely mood. High detail, intricate edges, poster quality. "
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

# Each terrain is a whole scene, so sets differ in more than the landmark.
_FOREST = ("Far back: tall mountain ranges with sharp faceted peaks. Middle: many overlapping ridges blanketed in "
           "dense pine forest, every forest layer made of hundreds of jagged pine and spruce silhouettes. ")
_FOREST_FRONT = (" Foreground: large, detailed near-black pine trees with visible branch tiers framing the left and "
                 "right edges, and a rocky ridge with grass and scattered boulders along the bottom.")
TERRAINS = {  # the first six are the original Firewatch forest scenes
    "tower": _FOREST + "On a rocky outcrop in the near-middle ground stands a tall wooden fire lookout tower on a "
             "lattice of stilts with a small cabin on top, drawn as a detailed silhouette." + _FOREST_FRONT,
    "ridge": _FOREST + "On a high ridge to one side stands a wooden fire lookout tower with a cabin on top, small "
             "against the mountains, with a winding trail leading up to it." + _FOREST_FRONT,
    "lake": _FOREST + "A fire lookout tower stands on a hilltop above a still mountain lake that mirrors the forest "
            "and sky." + _FOREST_FRONT,
    "river": _FOREST + "A winding river glints through the valley floor between the forested ridges, with a distant "
             "lookout tower on a far hill." + _FOREST_FRONT,
    "canyon": _FOREST + "The ridges open into a deep canyon with layered faceted rock walls, a lookout tower perched "
              "on the rim." + _FOREST_FRONT,
    "meadow": _FOREST + "A wide open alpine meadow stretches across the middle distance, with a lone lookout tower "
              "beyond it." + _FOREST_FRONT,
    "fjord": "A deep Norwegian fjord seen from high above the water: sheer faceted cliff walls plunge into still "
             "dark water that mirrors the sky and winds away between the mountains, a thin waterfall ribbons down "
             "one cliff, and a tiny red boathouse with a wooden jetty sits on a grassy shelf by the water. "
             "Foreground: a bare rock ledge with heather and a few slender birches on one side only, leaving the "
             "view open.",
    "island": "A wide calm lake fills most of the middle distance with a small rocky island crowned by three pines "
              "and a tiny cabin; low rounded hills and a soft far shoreline behind it. Foreground: a pebble beach "
              "with tall reeds and an upturned wooden canoe; open sky and no trees framing the edges.",
    "coast": "A rugged sea coast: layered headlands and tall sea stacks recede into the haze, waves break in white "
             "lines on the rocks, and a lighthouse with a keeper's cottage stands on the nearest headland. "
             "Foreground: a cliff top of wind-bent grass and one wind-sculpted pine leaning in from the edge.",
    "highland": "Bare rolling highland moors with no forest: long grassy ridges fold into the distance under a big "
                "sky, a dry stone wall winds over them to a small stone hut, with scattered boulders and a distant "
                "range of rounded mountains. Foreground: heather and a lone twisted tree.",
    "waterfall": "A tall waterfall pours from a high cliff into a misty gorge, a rope bridge spans the gorge in the "
                 "middle distance, and terraced cliffs with clinging pines rise on both sides. Foreground: mossy "
                 "boulders, ferns and one huge old pine leaning in from the side.",
    "mesa": "A red rock desert: flat-topped mesas and buttes layered into the distance, a dry wash winding through "
            "the valley floor, junipers and sagebrush, and a weathered wooden lookout cabin on the nearest mesa. "
            "Foreground: slickrock ledges and a gnarled juniper.",
}

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


# A month ahead of the calendar, so the desktop gets ready for the next season (snow from November).
SEASON_OF_MONTH = {11: "winter", 12: "winter", 1: "winter", 2: "winter", 3: "spring", 4: "spring",
                   5: "summer", 6: "summer", 7: "summer", 8: "autumn", 9: "autumn", 10: "autumn"}

SEASON_SCENE = {
    "winter": "Deep winter: thick snow blankets the ground, the rocks and every pine branch, the peaks are "
              "snow-capped and any lake or river is frozen white.",
    "spring": "Late spring: fresh meadow grass and a scattering of tiny wildflowers, the last snow only on the "
              "highest peaks. Paint it all in the image's existing palette: no bright green and no new colours; "
              "the grass is a slightly lighter, softer shade of the same hue, the flowers are small pale specks, "
              "and the foreground trees and ground stay dark silhouettes.",
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
    "spring": "Keep the fresh grass and tiny wildflowers, in the new palette's colours only: no green, "
              "and the foreground stays dark.",
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


def master(key, phase):
    """A set's full-size image for one phase (WebP: the repo stays small)."""
    return LIBRARY / key / f"{phase}.webp"


def cache_dir(key):
    d = CACHE / key
    d.mkdir(parents=True, exist_ok=True)
    return d


def _save_master(img, path):
    img.save(path, "WEBP", quality=95, method=6)


def complete_sets():
    if not LIBRARY.exists():
        return []
    return sorted(
        p.name for p in LIBRARY.iterdir()
        if p.is_dir() and all(master(p.name, phase).exists() for phase in PHASES)
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


def _fresh_terrain():
    """A terrain the library has fewest sets of, so new sets look different."""
    counts = {t: 0 for t in TERRAINS}
    for key in complete_sets():
        t = _meta(key).get("terrain")
        if t in counts:
            counts[t] += 1
    least = min(counts.values())
    return random.choice([t for t, n in counts.items() if n == least])


def recolour(client, base, look, phase):
    print(f"  recolouring {phase}")
    extra = (WEATHER_PHASE_EXTRA if look in WEATHER_SCENE else PHASE_EXTRA)[phase]
    extra = f"{extra} {KEEP_LOOK.get(look, '')}".strip()
    return _generate_image(client, [RECOLOUR_PROMPT.format(extra=extra, palette=PALETTES[phase]), base])


def generate_set(key, look=None, source=None, terrain=None):
    """Make a set: a new landscape (of a terrain), or with source=<set key> a season/weather copy of one."""
    from google import genai

    client = genai.Client(api_key=os.getenv("GEMINI_API_KEY"))
    look = look or season_of(datetime.date.today())
    tmp = LIBRARY / f".{key}.tmp"
    shutil.rmtree(tmp, ignore_errors=True)
    tmp.mkdir(parents=True)

    if source:
        feature = _meta(source).get("feature", "")
        terrain = _meta(source).get("terrain")
        print(f"Converting {source} to {look} as {key}")
        prompt = (WEATHER_CONVERT_PROMPT.format(scene=WEATHER_SCENE[look]) if look in WEATHER_SCENE
                  else CONVERT_PROMPT.format(scene=SEASON_SCENE[look]))
        base = _generate_image(client, [prompt, Image.open(master(source, "day"))])
    else:
        terrain = terrain or _fresh_terrain()
        feature = TERRAINS[terrain]
        print(f"Generating {key} ({terrain}, {look})")
        scene = f"{feature} {SEASON_SCENE[look] if look in SEASON_SCENE else WEATHER_SCENE[look]}".strip()
        base = _generate_image(client, BASE_PROMPT.format(feature=scene, palette=PALETTES["day"]))
    _save_master(base, tmp / "day.webp")
    for phase in ["dawn", "golden", "night"]:
        _save_master(recolour(client, base, look, phase), tmp / f"{phase}.webp")

    (tmp / "meta.json").write_text(json.dumps({
        "created": datetime.date.today().isoformat(),
        "model": MODEL,
        "feature": feature,
        **({"terrain": terrain} if terrain else {}),
        **({"weather": look} if look in WEATHER_SCENE else {"season": look}),
        **({"source": source} if source else {}),
    }, indent=2))
    final = LIBRARY / key
    shutil.rmtree(final, ignore_errors=True)
    tmp.rename(final)
    _features(key, detect=True)  # where the water and waterfalls are, for the live page


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
    """This season's sets once there are a couple; before that, plain sets plus this season's."""
    season = season_of(date)
    matching = [s for s in sets if metas[s].get("season") == season]
    if len(matching) >= 2:
        return matching
    # Plain (summer or undressed) sets fit any time of year; dressed ones only in their own season.
    return [s for s in sets if metas[s].get("season") in (None, "summer", season)] or sets


def _seeded_pick(date, pool):
    yesterday = _seeded_choice(date - datetime.timedelta(days=1), pool)
    return _seeded_choice(date, [s for s in pool if s != yesterday] or pool)


def _sun_times(date):
    s = sun(PLACE.observer, date=date, tzinfo=PLACE.timezone)
    sunrise, sunset = s["sunrise"], s["sunset"]
    try:  # around midsummer southern Norway never gets 12 degrees below the horizon
        first = nautical_dawn(PLACE.observer, date=date, tzinfo=PLACE.timezone, depression=12)
        last = nautical_dusk(PLACE.observer, date=date, tzinfo=PLACE.timezone, depression=12)
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
    folder = cache_dir(master_path.parent.name)
    out = folder / f"{master_path.stem}_{width}x{height}_{stamp}.png"
    if out.exists():
        return out
    for stale in folder.glob(f"{master_path.stem}_{width}x{height}*.png"):
        stale.unlink()
    img = Image.open(master_path)
    scale = max(width / img.width, height / img.height)
    img = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    left = round((img.width - width) * align)
    top = (img.height - height) // 2
    tmp = out.with_name(f".{out.name}.{os.getpid()}.png")  # atomic: another run may read it meanwhile
    img.crop((left, top, left + width, top + height)).save(tmp)
    os.replace(tmp, out)
    return out


def _display_crops(set_key, phase, displays):
    source = master(set_key, phase)
    main_x = displays[0]["x"]  # NSScreen.screens[0] is the main display
    out = []
    for d in displays:
        align = 0.5 if d["x"] == main_x else (0.0 if d["x"] < main_x else 1.0)
        out.append(crop_for(source, round(d["w"] * d["k"]), round(d["h"] * d["k"]), align))
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


def _skyline(paths, suns=(), guide=None):
    """Per column (240 samples), the height where the mountains start, as a fraction from the top.

    With a guide (a traced line, [[x, y], ...] fractions of the crop, from the set's features.json), each
    column takes the strongest colour step near the guide: clouds, glow bands and the moon sit far from
    it, and the step puts the line exactly on the ridge, tree tip or tower roof.
    Without one: the first strong colour step from the top. Night works best: the sky is dark against lit
    ridges, while at dawn pale peaks melt into the sky. Glows and clouds give false hits that sit too high
    and differ per image, so with several images the lowest hit is the real ridge. The sun/moon discs
    (suns: [x, y, r] fractions, as from _phase_info) are skipped so they don't count as peaks.
    """
    import numpy as np
    from scipy.ndimage import median_filter, uniform_filter

    lines = []
    for path in paths:
        small = _small(path)
        h, ww = small.shape[:2]
        sm = uniform_filter(small, size=(7, 7, 1))
        step = np.zeros((h, ww))
        step[2:-2] = np.abs(sm[4:] - sm[:-4]).sum(axis=2)  # colour change across each row
        if guide:
            gx, gy = np.asarray(guide, float).T
            g = np.interp((np.arange(ww) + 0.5) / ww, gx, gy) * h
            rows = np.arange(h)[:, None]
            near = (rows > g - 0.04 * h) & (rows < g + 0.04 * h)
            score = np.where(near, step - 600 * np.abs(rows - g) / h, -1)  # prefer edges close to the guide
            first = np.where(score.max(axis=0) > 30, score.argmax(axis=0), g).astype(float)
            lines.append(first[::2] / h)
            continue
        hit = step[int(h * 0.05):] > 40
        first = (np.where(hit.any(axis=0), hit.argmax(axis=0), int(h * 0.55)) + int(h * 0.05)).astype(float)
        for sx, sy, sr in suns:  # bridge straight across under the disc and its glow
            r = max(sr * 5, 0.045) * ww
            cols = np.abs(np.arange(ww) - sx * ww) < r
            cols &= first < sy * h + r  # only where the hit is the disc itself
            if cols.any() and not cols.all():
                first[cols] = np.interp(np.flatnonzero(cols), np.flatnonzero(~cols), first[~cols])
        lines.append(first[::2] / h)
    ridge = median_filter(np.max(lines, axis=0), size=3 if guide else 9, mode="nearest")
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


def _series():
    """MET Norway's hourly forecast for PLACE (refetched every 30 min, last copy kept offline)."""
    try:
        cached = json.loads(WEATHER_FILE.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        cached = {}
    if cached.get("url") != WEATHER_URL:  # first run or moved: the old place's forecast is no use
        cached = {}
    fetched = cached.get("fetched")
    if not fetched or datetime.datetime.now() - datetime.datetime.fromisoformat(fetched) > WEATHER_MAX_AGE:
        try:
            cached = {**_fetch_forecast(cached), "url": WEATHER_URL}
            WEATHER_FILE.write_text(json.dumps(cached))
        except Exception as e:  # offline: keep the last forecast if there is one
            print(f"Weather fetch failed: {e}", file=sys.stderr)
    return cached.get("forecast", {}).get("properties", {}).get("timeseries", [])


def _when(entry):
    return datetime.datetime.fromisoformat(entry["time"].replace("Z", "+00:00"))


def _symbol(entry):
    data = entry["data"]
    for span in ("next_1_hours", "next_6_hours", "next_12_hours"):
        if span in data:
            return data[span]["summary"]["symbol_code"]
    return ""


def _hour(entry):
    return entry["data"].get("next_1_hours", {}).get("details", {})


def weather(now):
    """The weather here for this hour from MET Norway, cached; None when unavailable."""
    series = _series()
    hour = now.astimezone(datetime.timezone.utc).replace(minute=0, second=0, microsecond=0)
    entry = next((e for e in series if _when(e) >= hour), None)
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


def forecast(now, hours=8, step=3, days=5):
    """The next hours (every `step`) and days for the live page's forecast panel; None when unavailable."""
    series = _series()
    hour = now.astimezone(datetime.timezone.utc).replace(minute=0, second=0, microsecond=0)
    ahead = [e for e in series if _when(e) >= hour]
    if not ahead:
        return None
    temp = lambda e: round(e["data"]["instant"]["details"].get("air_temperature", 0.0))
    rain = lambda e, span: e["data"].get(span, {}).get("details", {}).get("precipitation_amount", 0.0)
    first = ahead[0]
    upcoming = [e for e in ahead[1:] if (_when(e) - _when(first)).total_seconds() % (step * 3600) == 0][:hours]
    tz = zoneinfo.ZoneInfo(PLACE.timezone)
    by_day = {}
    for e in ahead:
        by_day.setdefault(_when(e).astimezone(tz).date(), []).append(e)
    summary = []
    for date, entries in list(by_day.items())[:days]:
        noon = min(entries, key=lambda e: abs(_when(e).astimezone(tz).hour - 13))
        hourly = [e for e in entries if "next_1_hours" in e["data"]]
        precip = (sum(rain(e, "next_1_hours") for e in hourly) if len(hourly) >= len(entries) - 1
                  else sum(rain(e, "next_6_hours") for e in entries if _when(e).hour % 6 == 0))
        summary.append({"date": date.isoformat(), "min": min(map(temp, entries)), "max": max(map(temp, entries)),
                        "symbol": _symbol(noon), "precip": round(precip, 1)})
    details = first["data"]["instant"]["details"]
    return {
        "place": PLACE.name,
        "now": {"temp": temp(first), "symbol": _symbol(first), "wind": round(details.get("wind_speed", 0.0)),
                "precip": round(rain(first, "next_1_hours"), 1)},
        # Chance of rain (%) hour by hour for the next 4 hours, for the panel's line chart.
        # plus the expected rain (mm) and MET's likely range (min-max), as yr draws it.
        "chance": [{"t": int(_when(e).timestamp() * 1000),
                    "p": round(_hour(e).get("probability_of_precipitation", 0)),
                    "mm": _hour(e).get("precipitation_amount", 0.0),
                    "lo": _hour(e).get("precipitation_amount_min", 0.0),
                    "hi": _hour(e).get("precipitation_amount_max", 0.0)}
                   for e in ahead[:5]],
        "hours": [{"t": int(_when(e).timestamp() * 1000), "temp": temp(e), "symbol": _symbol(e),
                   "precip": round(rain(e, "next_1_hours") or rain(e, "next_6_hours") / 6, 1)} for e in upcoming],
        "days": summary,
    }


def _scene(set_key, width, height, crops):
    """Sun/moon, sky colours and skyline for the page's effects; cached per set and size."""
    info_file = cache_dir(set_key) / f"scene_{width}x{height}.json"
    if info_file.exists():
        info = json.loads(info_file.read_text())
        if info.get("v") == SCENE_VERSION and info.get("features") == _features_file(set_key).exists():
            return info
    info = {phase: _phase_info(crops[phase]) for phase in PHASES}
    # A season/weather copy has the same layout as its source, whose clear sky gives a cleaner skyline
    # than clouds, rain or snow.
    source = _meta(set_key).get("source")
    traced = _features(set_key).get("skyline")
    guide = [[x, y] for y, x, _, _ in (_to_crop([y, x, y, x], master(set_key, "night"), width, height)
                                       for x, y in traced)] if traced else None
    if source in complete_sets():
        night = crop_for(master(source, "night"), width, height, 0.5)
        info["skyline"] = _skyline([night], [_phase_info(night)["sun"]], guide)
    else:
        info["skyline"] = _skyline([crops["night"]], [info["night"]["sun"]], guide)
    info.update(_masks(set_key, crops, width, height, info["skyline"]))
    info["v"] = SCENE_VERSION
    info["features"] = _features_file(set_key).exists()  # recompute once detection has run
    info_file.write_text(json.dumps(info))
    return info


SCENE_VERSION = 4  # bump when the scene analysis changes, to recompute cached scenes
DETECT_MODEL = "gemini-3.8-flash"  # text answer only: a fraction of a cent per set
DETECT_PROMPT = (
    "This is a landscape illustration. Find (1) every open water surface that would show reflections or "
    "waves, such as a lake, river, sea or fjord (not snow, not ice, not sky), and (2) every waterfall. "
    'Answer JSON only: {"water": [[ymin, xmin, ymax, xmax], ...], "waterfalls": [[ymin, xmin, ymax, xmax], ...]} '
    "with coordinates from 0 to 1000; use empty lists when there are none."
)


def _features_file(set_key):
    """A season/weather copy shares its source's layout, so it uses the source's answer."""
    source = _meta(set_key).get("source")
    return LIBRARY / (source if source in complete_sets() else set_key) / "features.json"


def _features(set_key, detect=False):
    """Water and waterfall boxes (fractions of the master image): features.json in the set.

    With detect, a missing file is filled by a Gemini vision call (done once, when a set is made);
    the regular runs never call the API.
    """
    cache = _features_file(set_key)
    key = cache.parent.name
    if cache.exists():
        return json.loads(cache.read_text())
    if not detect:
        return {"water": [], "waterfalls": []}
    from google import genai
    from google.genai import types

    client = genai.Client(api_key=os.getenv("GEMINI_API_KEY"))
    img = Image.open(master(key, "day")).convert("RGB")
    img.thumbnail((1536, 1536))
    try:
        resp = client.models.generate_content(
            model=DETECT_MODEL, contents=[DETECT_PROMPT, img],
            config=types.GenerateContentConfig(response_mime_type="application/json"))
        raw = json.loads(resp.text)
    except Exception as e:  # no water animation is fine; try again next time
        print(f"Feature detection failed for {key}: {e}", file=sys.stderr)
        return {"water": [], "waterfalls": []}
    out = {k: [[round(v / 1000, 4) for v in box] for box in raw.get(k, []) if len(box) == 4]
           for k in ("water", "waterfalls")}
    cache.write_text(json.dumps(out))
    return out


def _to_crop(box, master, width, height):
    """[ymin, xmin, ymax, xmax] as master fractions -> the same in the centred crop."""
    with Image.open(master) as im:
        iw, ih = im.size
    scale = max(width / iw, height / ih)
    ox, oy = (iw * scale - width) / 2, (ih * scale - height) / 2
    y0, x0, y1, x1 = box
    f = lambda v, size, off, out: min(1, max(0, (v * size * scale - off) / out))
    return [f(y0, ih, oy, height), f(x0, iw, ox, width), f(y1, ih, oy, height), f(x1, iw, ox, width)]


def _masks(set_key, crops, width, height, skyline):
    """Water and waterfall masks (small PNGs next to the crops) and lit windows/lamps at night.

    Inside Gemini's boxes, water is the smooth part (no texture) and a waterfall the bright part.
    Lights are small warm-yellow spots below the skyline in the night image.
    """
    import numpy as np
    from scipy.ndimage import label, uniform_filter

    out = {"lights": []}
    night = _small(crops["night"])  # 480 wide
    h, w = night.shape[:2]
    look = _meta(set_key).get("season")
    feats = _features(set_key)
    lum = night.mean(axis=2)
    # Water mirrors the sky: how far each pixel's colour is from the nearest sky colour, by day and by
    # night (land can match one palette by chance, rarely both).
    line = np.asarray(skyline)[((np.arange(w) + 0.5) / w * len(skyline)).astype(int)]
    above = (np.arange(h)[:, None] / h) < line[None, :] - 0.02
    sky_dist = np.zeros((h, w))
    for img in (night, _small(crops["day"])):
        sky = img[above]
        sky = sky[np.argsort(sky.sum(axis=1))][:: max(1, len(sky) // 80)]
        sky_dist = np.maximum(sky_dist, np.sqrt(((img[:, :, None, :] - sky[None, None]) ** 2).sum(-1)).min(-1))
    for kind in ("water", "waterfalls"):
        if look == "winter":  # frozen
            continue
        mask = np.zeros((h, w), bool)
        for box in feats.get(kind, []):
            y0, x0, y1, x1 = _to_crop(box, master(set_key, "night"), width, height)
            ys, xs = slice(int(y0 * h), int(np.ceil(y1 * h))), slice(int(x0 * w), int(np.ceil(x1 * w)))
            if not lum[ys, xs].size:
                continue
            if kind == "water":
                mask[ys, xs] |= sky_dist[ys, xs] < 15
            else:  # brighter than the cliffs beside it, below the ridge (not the sky in the box)
                # The falls fill most of a tight box, so compare with a strip twice its width each side.
                pad = max(2, xs.stop - xs.start) * 2
                wide = slice(max(0, xs.start - pad), min(w, xs.stop + pad))
                cliffs = np.median(lum[ys, wide], axis=1, keepdims=True)
                mask[ys, xs] |= (lum[ys, xs] - cliffs > 25) & ~above[ys, xs]
        if mask.sum() > 20:
            name = f"{kind}_{width}x{height}.png"
            Image.fromarray((uniform_filter(mask.astype(np.float32), 3) * 255).astype(np.uint8)).save(
                cache_dir(set_key) / name)
            ys, xs = np.nonzero(mask)
            out[kind] = {"mask": name, "box": [round(float(ys.min()) / h, 3), round(float(xs.min()) / w, 3),
                                               round(float(ys.max() + 1) / h, 3), round(float(xs.max() + 1) / w, 3)]}
    # Lights: warm, bright and small, below the ridge line. Copies share their source's layout, and their
    # own night can have false lights (orange autumn leaves) or hidden ones (rain), so use the source.
    source = _meta(set_key).get("source")
    lit = crop_for(master(source, "night"), width, height, 0.5) if source in complete_sets() else crops["night"]
    big = np.asarray(Image.open(lit).convert("RGB").resize((960, round(960 * h / w))), np.float32)
    r, g, b = big[..., 0], big[..., 1], big[..., 2]
    glow = big.mean(axis=2)
    warm = (r > 215) & (g > 160) & (b < 160) & (r - b > 80)
    warm &= glow - uniform_filter(glow, size=21) > 45  # a lit spot in the dark, not orange foliage
    rows = np.arange(big.shape[0])[:, None] / big.shape[0]
    cols = ((np.arange(big.shape[1]) + 0.5) / big.shape[1] * len(skyline)).astype(int)
    warm &= rows > np.asarray(skyline)[cols][None, :] - 0.02
    labels, n = label(warm)
    spots = []
    for i in range(1, n + 1):
        ys, xs = np.nonzero(labels == i)
        if 1 <= len(ys) <= 80:
            spots.append((len(ys), xs.mean() / big.shape[1], ys.mean() / big.shape[0]))
    lights = []
    for size, x, y in sorted(spots, reverse=True):  # neighbouring windows become one light
        if all(abs(x - lx) > 0.02 or abs(y - ly) > 0.03 for lx, ly, _ in lights):
            lights.append([round(float(x), 4), round(float(y), 4), round(float(min(0.004, 0.0012 * np.sqrt(size))), 4)])
    out["lights"] = lights[:10]
    return out


def _thumb(src, dst, width=640):
    if not dst.exists() or dst.stat().st_mtime < src.stat().st_mtime:
        img = Image.open(src).convert("RGB")
        img.resize((width, round(width * img.height / img.width)), Image.LANCZOS).save(dst, quality=85)
    return dst


def write_gallery(display):
    """GALLERY_DIR: every set, animated by the live page in any weather and time of day."""
    thumbs = GALLERY_DIR / "thumbs"
    thumbs.mkdir(parents=True, exist_ok=True)
    width, height = round(display["w"] * display["k"]), round(display["h"] * display["k"])
    sets = {}
    for key in complete_sets():
        print(f"  {key}")
        crops = {phase: crop_for(master(key, phase), width, height, 0.5) for phase in PHASES}
        meta = _meta(key)
        sets[key] = {
            "images": {phase: f"../cache/{key}/{crop.name}" for phase, crop in crops.items()},
            "scene": _scene(key, width, height, crops),
            "look": meta.get("weather") or meta.get("season"),
            "terrain": meta.get("terrain"),
            "masks": _mask_paths(_scene(key, width, height, crops), f"../cache/{key}/"),
            "feature": meta.get("feature", ""),
            "thumb": f"thumbs/{_thumb(master(key, 'day'), thumbs / f'{key}.jpg').name}",
        }
    for old in thumbs.iterdir():
        if old.stem not in sets:
            old.unlink()
    (GALLERY_DIR / "data.js").write_text(f"window.GALLERY = {json.dumps({'sets': sets})};\n")
    shutil.copyfile(GALLERY_PAGE, GALLERY_DIR / "index.html")
    return GALLERY_DIR / "index.html"


def _mask_paths(scene, prefix):
    return {k: prefix + scene[k]["mask"] for k in ("water", "waterfalls") if k in scene}


# --- Tren: this week's training plan for the live page's Tren panel ------------------------------
# Read straight from Tren's database with the read-only role the Tren ops console uses
# (PROD_RO_DATABASE_URL in ~/.tren-ops/secrets/prod-ro.env); whose plan is TREN_UID in ~/.dotfiles/.env.
TREN_DB_ENV = Path.home() / ".tren-ops/secrets/prod-ro.env"
TREN_FILE = WORK / "tren.json"  # the last good week, shown when the database can't be reached
TREN_SQL = """
    select p.date, p.slot, p.session_type, p.sport, p.distance_km, p.duration_min, p.status,
           p.matched_activity_id is not null, p.start_time, p.prescription, e.distance_km, e.duration_min
    from planned_sessions p left join enriched_activities e on e.id = p.matched_activity_id
    where p.uid = %s and p.date between %s and %s and p.status <> 'canceled' and p.session_type <> 'rest'
    order by p.date, case p.slot when 'am' then 0 when 'single' then 1 else 2 end"""
TREN_NAMES = {"threshold": "Threshold", "long_run": "Long run", "easy": "Easy", "z1_easy": "Easy",
              "race": "Race", "strength": "Strength", "vo2max_hill": "Hills", "hill": "Hills",
              "race_pace": "Race pace", "vo2max_classic": "VO2max"}  # other vo2*: Speed (Tren's speed-labels.ts)
TREN_KINDS = {"threshold": "threshold", "long_run": "long", "easy": "easy", "z1_easy": "easy",
              "race": "race", "strength": "strength"}


def _tren_label(session_type, sport, prescription):
    """Tren's name for a session, with its main rep block (e.g. "Threshold 3×6'") when the engine prescribed one."""
    name = TREN_NAMES.get(session_type) or ("Speed" if session_type.startswith("vo2") else
                                            (sport or session_type).replace("_", " ").capitalize())
    green = ((prescription or {}).get("scenarios") or {}).get("green") or {}
    blocks = [b for b in green.get("blocks") or [] if b.get("role") not in ("warmup", "cooldown")
              and (b.get("count") or 0) > 0 and (b.get("rep_min") or 0) > 0]
    if (prescription or {}).get("status") == "prescribed" and blocks:
        b = max(blocks, key=lambda b: b["count"] * b["rep_min"])
        rep = f"{round(b['rep_min'] * 60)}s" if b["rep_min"] < 1 else f"{b['rep_min']:g}'"
        return f"{name} {round(b['count'])}×{rep}", green.get("est_duration_min")
    return name, green.get("est_duration_min")


def _tren_fetch(uid, start, end):
    import psycopg  # only here, so the wallpaper runs without it
    url = dotenv_values(TREN_DB_ENV).get("PROD_RO_DATABASE_URL")
    if not url:
        raise RuntimeError(f"PROD_RO_DATABASE_URL missing from {TREN_DB_ENV}")
    with psycopg.connect(url, connect_timeout=3, options="-c statement_timeout=3000") as conn:
        return conn.execute(TREN_SQL, (uid, start, end)).fetchall()


def tren_week(today):
    """This week's Tren plan (Mon–Sun, plus the next two days once the week is nearly over); None when unavailable."""
    uid = os.environ.get("TREN_UID")
    if not uid:
        return None
    start = today - datetime.timedelta(days=today.weekday())
    end = max(start + datetime.timedelta(days=6), today + datetime.timedelta(days=2))
    try:
        rows = _tren_fetch(uid, start, end)
    except Exception as e:  # offline or the database is down: the last good copy of this week, if any
        print(f"Tren fetch failed: {e}", file=sys.stderr)
        try:
            cached = json.loads(TREN_FILE.read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            return None
        return cached if cached.get("week_start") == start.isoformat() else None
    days = {start + datetime.timedelta(days=i): [] for i in range((end - start).days + 1)}
    for (date, _slot, stype, sport, km, minutes, status, matched, time, rx, done_km, done_min) in rows:
        label, est_min = _tren_label(stype, sport, rx)
        done = status == "completed" or matched
        days[date].append({
            "kind": TREN_KINDS.get(stype) or ("vo2" if stype.startswith("vo2") or "hill" in stype else
                                              "cross" if sport not in (None, "running") else "other"),
            "label": label,
            "km": round(done_km if done and done_km else km or 0, 1) or None,
            "min": round(done_min if done and done_min else minutes or est_min or 0) or None,
            "status": "completed" if done else "skipped" if status == "skipped" else "planned",
            "plan_km": km or 0,
            "time": time,
        })
    week = [s for d, ss in days.items() if d <= start + datetime.timedelta(days=6) for s in ss]
    done = [s for s in week if s["status"] == "completed"]
    out = {
        "week": start.isocalendar().week,
        "week_start": start.isoformat(),
        "days": [{"date": d.isoformat(), "sessions": ss} for d, ss in days.items() if (d - start).days < 7],
        "next": [{"date": d.isoformat(), "sessions": ss} for d, ss in days.items() if (d - start).days >= 7],
        "total": {
            "planned_km": round(sum(s["km"] or 0 if s["status"] == "completed" else s["plan_km"]
                                    for s in week if s["status"] != "skipped"), 1),
            "done_km": round(sum(s["km"] or 0 for s in done), 1),
            "sessions": sum(s["status"] != "skipped" for s in week),
            "sessions_done": len(done),
            "done_min": round(sum(s["min"] or 0 for s in done)),
        },
    }
    for d in out["days"] + out["next"]:
        for sess in d["sessions"]:
            del sess["plan_km"]  # only for the total
    TREN_FILE.write_text(json.dumps(out))
    return out


def write_live(set_key, display, wx, preset=None):
    """Mirror today's set into LIVE_DIR so the page (and Plash) only needs that folder."""
    LIVE_DIR.mkdir(exist_ok=True)
    width, height = round(display["w"] * display["k"]), round(display["h"] * display["k"])
    images, crops, keep = {}, {}, {"index.html", "state.js"}
    for phase in PHASES:
        crops[phase] = crop_for(master(set_key, phase), width, height, 0.5)
        name = f"{set_key}_{crops[phase].name}"
        if not (LIVE_DIR / name).exists():
            os.link(crops[phase], LIVE_DIR / name)  # hard link: no extra disk
        images[phase] = name
        keep.add(name)
    info = _scene(set_key, width, height, crops)
    masks = _mask_paths(info, "")
    for kind, name in masks.items():
        live_name = f"{set_key}_{name}"
        if not (LIVE_DIR / live_name).exists():
            os.link(cache_dir(set_key) / name, LIVE_DIR / live_name)
        masks[kind] = live_name
        keep.add(live_name)
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
        "forecast": forecast(datetime.datetime.now().astimezone()),
        "preset": preset,  # a weather picked from the sketchybar menu; the page uses it over wx
        "tren": tren_week(today),  # the Tren panel: this week's training plan
        "look": _meta(set_key).get("weather") or _meta(set_key).get("season"),
        "season": season_of(today),  # the page's fallback for snow vs. leaves when a set has no look
        "terrain": _meta(set_key).get("terrain"),
        "masks": masks,
    }
    (LIVE_DIR / "state.js").write_text(f"window.WALLPAPER = {json.dumps(state)};\n")
    page = LIVE_DIR / "index.html"
    if not page.exists() or page.read_bytes() != LIVE_PAGE.read_bytes():
        shutil.copyfile(LIVE_PAGE, page)


def _start_plash(state):
    """Open Plash (which shows the live page) once per boot; quitting it then sticks until a restart."""
    try:
        boot = re.search(r"sec = (\d+)", subprocess.run(["sysctl", "-n", "kern.boottime"],
                         capture_output=True, text=True).stdout).group(1)
    except (AttributeError, OSError):
        return
    if state.get("plash_boot") == boot or not Path("/Applications/Plash.app").exists():
        return
    if subprocess.run(["pgrep", "-xq", "Plash"]).returncode != 0:
        subprocess.run(["open", "-gja", "Plash"])
        print("Started Plash")
    state["plash_boot"] = boot


def _today_weather(today, state):
    """The real weather now, or the preset picked for today (with what pick_set needs)."""
    preset = state.get("weather_overrides", {}).get(today.isoformat())
    wx = weather(datetime.datetime.now().astimezone())
    if preset in WEATHER_PRESETS:
        return {**(wx or {}), "kind": None, "thunder": False, **WEATHER_PRESETS[preset]}, preset
    return wx, None


def set_label(key, sets=None):
    """A short menu name: the terrain plus its look, with the set name when a terrain repeats."""
    sets = sets or complete_sets()
    meta = _meta(key)
    base = meta.get("source", key)
    terrain = _meta(base).get("terrain") or base
    twins = [s for s in sets if not _meta(s).get("source") and (_meta(s).get("terrain") or s) == terrain]
    name = f"{terrain} {base.rsplit('-', 1)[-1]}" if len(twins) > 1 else terrain
    look = meta.get("weather") or meta.get("season")
    return f"{name} · {look}" if look and look != "summer" else name


def _status(today, state, wx, preset):
    sets = complete_sets()
    current = pick_set(today, state, wx)
    return {
        "set": current,
        "label": set_label(current, sets) if current else None,
        "pinned": today.isoformat() in state.get("overrides", {}),
        "weather": preset or "auto",
        "place": PLACE.name,
        "real": (weather(datetime.datetime.now().astimezone()) or {}).get("symbol"),
        "sets": [{"key": s, "label": set_label(s, sets)} for s in sorted(sets, key=lambda s: set_label(s, sets))],
        "presets": list(WEATHER_PRESETS),
    }


# --- main --------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--generate", nargs="?", const="any", metavar="TERRAIN",
                        help=f"make a new set now, of a terrain ({', '.join(TERRAINS)}); "
                             "default: one the library has least of")
    parser.add_argument("--reroll", action="store_true", help="pick a different set for today")
    parser.add_argument("--at", help="preview the blend at HH:MM today (not saved to state)")
    parser.add_argument("--convert", nargs=2, metavar=("SET", "LOOK"),
                        help=f"make a copy of a set in another look ({', '.join(LOOKS)}), shown first today")
    parser.add_argument("--show", metavar="SET", help="show this set for the rest of today")
    parser.add_argument("--weather", metavar="PRESET",
                        help=f"use this weather for the rest of today ({', '.join(WEATHER_PRESETS)}, or auto)")
    parser.add_argument("--status", action="store_true", help="print today's set, weather and choices as JSON")
    parser.add_argument("--gallery", action="store_true",
                        help="build and open a click-through gallery of every set in any weather and time")
    args = parser.parse_args()
    if args.convert and args.convert[1] not in LOOKS:
        parser.error(f"look must be one of {', '.join(LOOKS)}")
    if args.weather and args.weather != "auto" and args.weather not in WEATHER_PRESETS:
        parser.error(f"weather must be one of {', '.join(WEATHER_PRESETS)}, or auto")

    LIBRARY.mkdir(parents=True, exist_ok=True)
    WORK.mkdir(parents=True, exist_ok=True)
    if args.gallery:
        print("Building gallery")
        page = write_gallery(screens()[0])
        subprocess.run(["open", page])
        print(page)
        return
    with open(LOCK_FILE, "w") as lock:
        try:
            # a choice from the menu waits for a running job; the 5-minute run just skips
            asked = args.show or args.weather or args.reroll
            fcntl.flock(lock, fcntl.LOCK_EX if asked else fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("Another wallpaper run is in progress")
            return

        state = load_state()
        if args.convert:
            source, look = args.convert
            generate_set(f"{source}-{look}", look=look, source=source)
        if args.generate:
            terrain = None if args.generate == "any" else args.generate
            if terrain and terrain not in TERRAINS:
                parser.error(f"terrain must be one of {', '.join(TERRAINS)}")
            terrain = terrain or _fresh_terrain()
            generate_set(f"{datetime.date.today().isoformat()}-{terrain}", look="summer", terrain=terrain)

        today = datetime.date.today()
        if args.weather:
            forced = {k: v for k, v in state.get("weather_overrides", {}).items() if k >= today.isoformat()}
            forced.pop(today.isoformat(), None)
            if args.weather != "auto":
                forced[today.isoformat()] = args.weather
            state["weather_overrides"] = forced
        if args.show == "auto":
            state.get("overrides", {}).pop(today.isoformat(), None)
        wx, preset = _today_weather(today, state)
        if args.status:
            print(json.dumps(_status(today, state, wx, preset)))
            return
        override = None
        if args.show and args.show != "auto":
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
        if signature != state.get("applied") or args.reroll or args.show or args.weather or args.generate or args.at or args.convert:
            paths = apply(set_key, a, b, t, displays)
            print(f"Wallpaper: {set_key} {a}->{b} {t:.2f} -> {[str(p) for p in paths]}")
            if args.at:
                state.pop("applied", None)  # the next normal run puts the real blend back
                save_state(state)
                return
            state["applied"] = signature
        try:  # the live page is extra; never let it stop the still wallpaper
            write_live(set_key, displays[0], wx, preset)
        except Exception as e:
            print(f"Live page update failed: {e}", file=sys.stderr)
        _start_plash(state)
        save_state(state)


if __name__ == "__main__":
    main()

import subprocess
import datetime
from dotenv import load_dotenv
import os
from google import genai
from google.genai import types
from PIL import Image, ImageStat

# Watch spending: https://console.cloud.google.com/billing/01B85F-1A6511-809A4F?project=gen-lang-client-0292679403&authuser=1
# Load environment variables from .env file
load_dotenv()

# Get the Gemini API key from environment variables
api_key = os.getenv("GEMINI_API_KEY")
client = genai.Client(api_key=api_key)


        # "Color palette: [#f5e0dc,#f2cdcd,#f5c2e7,#cba6f7,#f38ba8,#eba0ac,#fab387,#f9e2af,#a6e3a1,#94e2d5,#89dceb,#74c7ec,#89b4fa,#b4befe,#cdd6f4,#bac2de,#a6adc8,#9399b2,#7f849c,#6c7086,#585b70,#45475a,#313244,#1e1e2e,#181825,#11111b]. "


def trim_white_border(img, threshold=230):
    """Remove white/near-white borders from all edges."""
    pixels = img.load()
    w, h = img.size

    def is_near_white(pixel):
        return all(c >= threshold for c in pixel[:3])

    def row_is_white(y):
        return all(is_near_white(pixels[x, y]) for x in range(0, w, max(1, w // 50)))

    def col_is_white(x):
        return all(is_near_white(pixels[x, y]) for y in range(0, h, max(1, h // 50)))

    top = 0
    while top < h and row_is_white(top):
        top += 1
    bottom = h - 1
    while bottom > top and row_is_white(bottom):
        bottom -= 1
    left = 0
    while left < w and col_is_white(left):
        left += 1
    right = w - 1
    while right > left and col_is_white(right):
        right -= 1

    if top > 0 or bottom < h - 1 or left > 0 or right < w - 1:
        return img.crop((left, top, right + 1, bottom + 1))
    return img


def generate_landscape():
    prompt = (
        "Generate a single image only, no text response. "
        "Create a dark and mystic forest landscape from a random continent, viewed from a height, in a painterly digital illustration style. "
        "CRITICAL: The artwork must extend to every pixel of the image edge. There must be absolutely NO white margins, NO borders, NO frame, NO canvas effect, NO surrounding whitespace. "
        "The scene must bleed off all four edges as if the viewer is looking through a window into the landscape. "
        "Do not render this as a painting on a surface. Render it as a full-bleed wallpaper image in 16:9 aspect ratio. "
        "Use a rich, vibrant color palette with many varied hues blended throughout the scene — deep greens, blues, purples, warm oranges, magentas, teals, and golden highlights. Embrace bold, saturated colors with atmospheric depth while keeping the mystical mood. "
        "No text, no labels, no design elements."
    )

    response = client.models.generate_content(
        model="gemini-2.5-flash-image",
        contents=prompt,
        config=types.GenerateContentConfig(
            response_modalities=["IMAGE", "TEXT"],
            image_config=types.ImageConfig(
                aspect_ratio="16:9",
            ),
        ),
    )

    timestamp = datetime.datetime.now().strftime("%Y-%m-%d_%H_%M")
    directory = os.path.expanduser("~/Pictures/wallpaperscript")
    if not os.path.exists(directory):
        os.makedirs(directory)
    image_path = f"{directory}/landscape_{timestamp}.png"

    for part in response.candidates[0].content.parts:
        if part.inline_data is not None and part.inline_data.data is not None:
            with open(image_path, "wb") as f:
                f.write(part.inline_data.data)
            img = Image.open(image_path)
            # Strip white/near-white borders if Gemini added a frame
            img = trim_white_border(img)
            # Upscale and center-crop to match ultrawide display (3840x1600)
            # Scale so width matches 3840, then crop height to 1600
            scale = 3840 / img.width
            img = img.resize((3840, round(img.height * scale)), Image.LANCZOS)
            top = (img.height - 1600) // 2
            img = img.crop((0, top, 3840, top + 1600))
            img.save(image_path)
            break

    return image_path


def set_wallpaper(image_path):
    subprocess.run([
        "osascript", "-e",
        f'tell application "Finder" to set desktop picture to POSIX file "{image_path}"'
    ], check=True)


if __name__ == "__main__":
    image_path = generate_landscape()
    set_wallpaper(image_path)

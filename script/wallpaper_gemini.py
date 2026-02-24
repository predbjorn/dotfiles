import subprocess
import datetime
from dotenv import load_dotenv
import os
from google import genai
from google.genai import types

# Watch spending: https://console.cloud.google.com/billing/01B85F-1A6511-809A4F?project=gen-lang-client-0292679403&authuser=1
# Load environment variables from .env file
load_dotenv()

# Get the Gemini API key from environment variables
api_key = os.getenv("GEMINI_API_KEY")
client = genai.Client(api_key=api_key)


def generate_landscape():
    prompt = (
        "Generate a single image only, no text response. "
        "Create a dark and mystic forest landscape from a random continent, viewed from a height, in a painterly digital illustration style. "
        "Color palette: [#f5e0dc,#f2cdcd,#f5c2e7,#cba6f7,#f38ba8,#eba0ac,#fab387,#f9e2af,#a6e3a1,#94e2d5,#89dceb,#74c7ec,#89b4fa,#b4befe,#cdd6f4,#bac2de,#a6adc8,#9399b2,#7f849c,#6c7086,#585b70,#45475a,#313244,#1e1e2e,#181825,#11111b]. "
        "CRITICAL: The artwork must extend to every pixel of the image edge. There must be absolutely NO white margins, NO borders, NO frame, NO canvas effect, NO surrounding whitespace. "
        "The scene must bleed off all four edges as if the viewer is looking through a window into the landscape. "
        "Do not render this as a painting on a surface. Render it as a full-bleed wallpaper image in 16:9 aspect ratio. "
        "No text, no labels, no design elements."
    )

    response = client.models.generate_content(
        model="gemini-2.5-flash-image",
        contents=prompt,
        config=types.GenerateContentConfig(
            response_modalities=["IMAGE", "TEXT"],
        ),
    )

    timestamp = datetime.datetime.now().strftime("%Y-%m-%d_%H_%M")
    directory = "/Users/predbjorn/Pictures/wallpaperscript"
    if not os.path.exists(directory):
        os.makedirs(directory)
    image_path = f"{directory}/landscape_{timestamp}.png"

    for part in response.candidates[0].content.parts:
        if part.inline_data is not None:
            with open(image_path, "wb") as f:
                f.write(part.inline_data.data)
            break

    return image_path


def set_wallpaper(image_path):
    script = f'''
    osascript -e 'tell application "System Events" to set picture of every desktop to "{image_path}"'
    '''
    subprocess.run(script, shell=True, check=True)


if __name__ == "__main__":
    image_path = generate_landscape()
    set_wallpaper(image_path)

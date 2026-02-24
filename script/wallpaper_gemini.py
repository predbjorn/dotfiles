import subprocess
import datetime
from dotenv import load_dotenv
import os
from google import genai
from google.genai import types

# Load environment variables from .env file
load_dotenv()

# Get the Gemini API key from environment variables
api_key = os.getenv("GEMINI_API_KEY")
client = genai.Client(api_key=api_key)


def generate_landscape():
    prompt = (
        "Generate an image only, no text response."
        "Main Theme: create a painting of a dark and mystic forest landscape from a random continent, viewed from a hight,"
        "Color pallete used in the painting:[#f5e0dc,#f2cdcd,#f5c2e7,#cba6f7,#f38ba8,#eba0ac,#fab387,#f9e2af,#a6e3a1,#94e2d5,#89dceb,#74c7ec,#89b4fa,#b4befe,#cdd6f4,#bac2de,#a6adc8,#9399b2,#7f849c,#6c7086,#585b70,#45475a,#313244,#1e1e2e,#181825,#11111b]"
        "It should only contain the \"Main Theme\" and no other elements in the foreground, background or surrounding space."
        "It should contain the \"Main Theme\" only once with no margins above, below or on either side."
        "The \"Main Theme\" should consume the entire 16:9 space."
        "It should not divide the \"Main Theme\" into separate parts of the image nor imply any variations of it."
        "It should not contain any text, labels, borders, measurements nor design elements of any kind."
        "The image should be suitable for digital printing without any instructional or guiding elements."
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

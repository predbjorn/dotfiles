import subprocess
from openai import OpenAI
import requests
import datetime

client = OpenAI(api_key="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")

# Set your OpenAI API key

def generate_landscape():
    # Define the prompt for an African landscape
    # prompt = (
    #     "Main Theme: create an image of a beautiful landscape from a random continent"
    #     "Style: Catppuccin Norwegian national romantic painting"
    #     "It should be colorful, realistic, minimalistic, and somewhat of a challenge to replicate."
    #     "It should only contain the “Main Theme” and no other elements in the foreground, background or surrounding space."
    #     "It should contain the “Main Theme” only once with no margins above, below or on either side."
    #     "The “Main Theme” should consume the entire 1792x1024 space."
    #     "It should not divide the “Main Theme” into separate parts of the image nor imply any variations of it."
    #     "It should not contain any text, labels, borders, measurements nor design elements of any kind."
    #     "The image should be suitable for digital printing without any instructional or guiding elements."
	# )
    prompt = (
        "Main Theme: create a painting of a dark and mystic forest landscape from a random continent, viewed from a hight,"
        "with the pallet of from this array: [#f5e0dc,#f2cdcd,#f5c2e7,#cba6f7,#f38ba8,#eba0ac,#fab387,#f9e2af,#a6e3a1,#94e2d5,#89dceb,#74c7ec,#89b4fa,#b4befe,#cdd6f4,#bac2de,#a6adc8,#9399b2,#7f849c,#6c7086,#585b70,#45475a,#313244,#1e1e2e,#181825,#11111b]"
        "It should only contain the “Main Theme” and no other elements in the foreground, background or surrounding space."
        "It should contain the “Main Theme” only once with no margins above, below or on either side."
        "The “Main Theme” should consume the entire 1792x1024 space."
        "It should not divide the “Main Theme” into separate parts of the image nor imply any variations of it."
        "It should not contain any text, labels, borders, measurements nor design elements of any kind."
        "The image should be suitable for digital printing without any instructional or guiding elements."
	)

    # Call the OpenAI DALL-E API
    response = client.images.generate(
		model="dall-e-3",
		prompt=prompt,
    	n=1,
    	size="1792x1024"
	)

    # # Extract the image URL from the response
    image_url = response.data[0].url

    # Download the image
    timestamp = datetime.datetime.now().strftime("%Y%m%d%H%M%S")
    image_path = f"/Users/predbjorn/Pictures/chat_wall/landscape_{timestamp}.png"
    print(image_path)
    image_data = requests.get(image_url).content
    with open(image_path, "wb") as image_file:
        image_file.write(image_data)

    return image_path

def set_wallpaper(image_path):
    # Use AppleScript to set the wallpaper on macOS
    script = f'''
    osascript -e 'tell application "System Events" to set picture of every desktop to "{image_path}"'
    '''
    subprocess.run(script, shell=True, check=True)

# Call the functions and set the wallpaper
if __name__ == "__main__":
    image_path = generate_landscape()
    set_wallpaper(image_path)
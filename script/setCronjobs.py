import os
import subprocess

# Define the cron job to check
cron_job = "0 12 * * * /usr/local/bin/python3.11 ~/.dotfiles/wallpaper.py"

# Get current crontab contents
def get_crontab():
    result = subprocess.run(['crontab', '-l'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return result.stdout.decode('utf-8')

# Check if the cron job is already in the crontab
def cron_job_exists(crontab_contents):
    return cron_job in crontab_contents

# Add the cron job to the crontab
def add_cron_job():
    # Get current crontab
    crontab_contents = get_crontab()

    # If the cron job is not already in crontab, add it
    if not cron_job_exists(crontab_contents):
        # Add the new cron job
        crontab_contents += f'\n{cron_job}\n'
        
        # Apply the new crontab
        subprocess.run(['crontab', '-'], input=crontab_contents.encode('utf-8'))
        print("Cron job added successfully.")
    else:
        print("Cron job already exists.")

# Run the function to ensure the cron job is in place
add_cron_job()
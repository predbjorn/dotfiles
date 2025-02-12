import os
import subprocess



# Define the cron jobs to check

# Get the path to the python executable using pyenv
python_path = subprocess.run(['pyenv', 'which', 'python'], stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout.decode('utf-8').strip()
dotfiles_path = os.getenv('DOTFILES')
if not dotfiles_path:
	dotfiles_path = '~/.dotfiles'
cron_jobs = [
	f"0 12 * * * cd {dotfiles_path} && {python_path} script/wallpaper.py >/tmp/stdout.log 2>/tmp/stderr.log",
	# Add more cron jobs here
	# f"29 10 * * * cd {dotfiles_path} && {python_path} script/wallpaper.py >/tmp/stdout.log 2>/tmp/stderr.log"
]

# Get current crontab contents
def get_crontab():
    result = subprocess.run(['crontab', '-l'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return result.stdout.decode('utf-8')

# Check if the cron job is already in the crontab
def cron_job_exists(crontab_contents, cron_job):
    return cron_job in crontab_contents

# Add the cron jobs to the crontab
def add_cron_jobs():
    # Get current crontab
    crontab_contents = get_crontab()

    # Iterate over each cron job and add if not already present
    for cron_job in cron_jobs:
        if not cron_job_exists(crontab_contents, cron_job):
            crontab_contents += f'\n{cron_job}\n'
            print(f"Cron job added: {cron_job}")
        else:
            print(f"Cron job already exists: {cron_job}")

    # Apply the new crontab
    subprocess.run(['crontab', '-'], input=crontab_contents.encode('utf-8'))

# Run the function to ensure the cron jobs are in place
add_cron_jobs()
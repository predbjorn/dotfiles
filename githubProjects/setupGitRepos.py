import os
import subprocess
from get_github_projects import get_github_projects

print("Setting up git repos...")
local_dir = os.path.expanduser("~/Hacking")
os.chdir(os.path.dirname(os.path.abspath(__file__)))
# Read the list of projects from the default file
projects = get_github_projects(local_dir)

for project in projects:
	project_url, project_subdir = project.split()
	if project_subdir.startswith("~/"):
		project_path = os.path.expanduser(project_subdir)
	else:
		project_path = os.path.join(local_dir, project_subdir)
	print(f"project_path {project_path}")
	print(f"isdir {not os.path.isdir(project_path)}")
	print(f"listdir {not os.listdir(project_path)}")
	if not os.path.isdir(project_path) or not os.listdir(project_path):
		print(f"Cloning {project_url} to {project_path}")
		os.makedirs(project_path, exist_ok=True)
		parent_dir = os.path.dirname(project_path)
		while not os.path.exists(parent_dir):
			parent_dir = os.path.dirname(parent_dir)
		last_folder_name = os.path.basename(project_path)
		os.chdir(parent_dir)
		subprocess.run(['gh', 'repo', 'clone', project_url, last_folder_name])
		os.chdir(local_dir)

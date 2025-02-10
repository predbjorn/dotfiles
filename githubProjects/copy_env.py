import os
import shutil
from get_github_projects import get_github_projects

local_dir = "~/Hacking"
dest_dir = "~/Hacking/variables"

# Read the list of projects from the default file
projects = get_github_projects(local_dir)

for project in projects:
    project_name, project_subdir = project.split()
    project_name = project_name.removesuffix('.git')
    if project_name.endswith('/'):
       project_name = project_name[:-1]
    project_dir = os.path.join(local_dir, project_subdir)
    
    if os.path.isdir(os.path.expanduser(project_dir)):
        for root, dirs, files in os.walk(os.path.expanduser(project_dir)):
            for file in files:
                if ".env" in file:
                   env_file = os.path.join(root, file)
                   relative_path = os.path.relpath(env_file, os.path.expanduser(project_dir))
                   dest_path = os.path.join(dest_dir, project_name, relative_path)
                   os.makedirs(os.path.dirname(os.path.expanduser(dest_path)), exist_ok=True)
                   shutil.copy2(env_file, os.path.expanduser(dest_path))
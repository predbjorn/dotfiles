import os
import shutil
from get_github_projects import get_github_projects

local_dir = "~/Hacking"
var_dir = "~/.variables"
os.chdir(os.path.dirname(os.path.abspath(__file__)))
# Read the list of projects from the default file
projects = get_github_projects(local_dir)

for project in projects:
    project_name, project_subdir = project.split()
    if project_name == "predbjorn/variables":
        continue
    if project_name.endswith('/'):
        project_name = project_name[:-1]
    if project_subdir.startswith("~/"):
        project_dir = os.path.expanduser(project_subdir)
    else:
        project_dir = os.path.join(local_dir, project_subdir)
    project_var_dir = os.path.join(var_dir, project_name)
    print(f"##################")
    print(f"project_dir {project_dir}")
    print(f"project_var_dir {project_var_dir}")
    print(f"##################")
    if os.path.isdir(os.path.expanduser(project_var_dir)):
        for root, dirs, files in os.walk(os.path.expanduser(project_var_dir)):
            for file in files:
                if ".env" in file:
                    env_file = os.path.join(root, file)
                    relative_path = os.path.relpath(env_file, os.path.expanduser(project_var_dir))
                    dest_path = os.path.join(project_dir, relative_path)
                    print(f"Copying {file} from {project_name} to {dest_path}")
                    os.makedirs(os.path.dirname(os.path.expanduser(dest_path)), exist_ok=True)
                    shutil.copy2(env_file, os.path.expanduser(dest_path))
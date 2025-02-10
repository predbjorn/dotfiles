import os

# Determine the file to read the list of projects from
override_file = './githubProject_local'
default_file = './githubProject'


def get_github_projects(local_dir = "~/Hacking"):
	# Read the list of projects from the default file
	with open(default_file, 'r') as file:
		projects = file.readlines()

	# Check if override file exists and update project paths if they exist in the override file
	if os.path.exists(override_file):
		with open(override_file, 'r') as file:
			override_projects = file.readlines()
		
		for i, project in enumerate(projects):
			project = project.split()[0]
			for override_project in override_projects:
				override_project = override_project.split()
				if override_project[0] == project and os.path.isdir(os.path.expanduser(os.path.join(local_dir, override_project[1]))):
					projects[i] = f"{project} {override_project[1]}\n"
					break
	return projects


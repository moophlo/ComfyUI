## [Unreleased]

### Added
Added a loop to the run.sh script that uses the `find` command to recursively search for
`requirements.txt` files in all subdirectories of /dockerx/ComfyUI/custom_nodes/. Each file
found is then processed with pip to install any listed dependencies.

### Added
- Extracted the base image tag from the Dockerfile’s FROM line and added it as an additional image tag during the push. This allows tracking of the underlying base image version used in the build.

### Added
- Updated the GitHub Actions workflow to derive the Docker image name dynamically from the GitHub repository name (using `${{ github.repository }}`), ensuring the image is tagged as `githubuser/repositoryname`.
- Modified the trigger so that the workflow runs only when the `Dockerfile` changes (using the `paths` filter) and on version tag pushes.
- Maintained existing tags for latest, commit SHA, semantic version (if applicable), and the base image tag from the Dockerfile.

### Added
- Modified the GitHub Actions workflow to convert the derived image name from `${{ github.repository }}` to all lowercase (using `tr`), ensuring that the Docker image name is always in lowercase.

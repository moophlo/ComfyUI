#!/usr/bin/env bash

set -Eeuo pipefail
[[ "${DEBUG:-0}" == "1" ]] && set -x

export FLASH_ATTENTION_TRITON_AMD_ENABLE="TRUE"
export PIP_DISABLE_PIP_VERSION_CHECK=1

COMFY_DIR="/dockerx/ComfyUI"
CUSTOM_DIR="$COMFY_DIR/custom_nodes"
MODELS_DIR="$COMFY_DIR/models"
VAE_APPROX_DIR="$MODELS_DIR/vae_approx"

# Default args if not provided
: "${COMMANDLINE_ARGS:=--listen --front-end-version Comfy-Org/ComfyUI_frontend@latest --use-split-cross-attention --reserve-vram 6}"

# Controls (all optional)
: "${UPDATE_ON_START:=0}"              # 1 = git fetch/reset on startup
: "${INSTALL_DEPS_ON_START:=0}"        # 1 = pip install requirements on startup
: "${INSTALL_FLASH_ATTN_ON_START:=0}"  # 1 = pip install flash-attn at runtime
: "${OFFLINE:=0}"                      # 1 = skip git/pip/wget network actions
: "${PIP_ARGS:=--timeout 180 --retries 25}"  # extra pip args

log() { echo "[$(date -Is)] $*"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }
}

git_sync() {
  # git_sync <path> <remote_branch> <clone_url> [clone_branch]
  local path="$1" remote_branch="$2" clone_url="$3" clone_branch="${4:-}"

  if [[ "$OFFLINE" == "1" ]]; then
    log "OFFLINE=1: skipping git operations for $path"
    return 0
  fi

  if [[ -d "$path/.git" ]]; then
    if [[ "$UPDATE_ON_START" == "1" ]]; then
      log "Updating $(basename "$path") -> $remote_branch"
      git -C "$path" fetch --prune origin
      git -C "$path" reset --hard "$remote_branch"
    else
      log "UPDATE_ON_START=0: not updating $(basename "$path")"
    fi
  else
    log "Cloning $(basename "$path")"
    if [[ -n "$clone_branch" ]]; then
      git clone -b "$clone_branch" "$clone_url" "$path"
    else
      git clone "$clone_url" "$path"
    fi
  fi
}

pip_install_req() {
  # pip_install_req <requirements_file>
  local req="$1"
  [[ -f "$req" ]] || return 0

  if [[ "$OFFLINE" == "1" ]]; then
    log "OFFLINE=1: skipping pip install -r $req"
    return 0
  fi

  log "pip install -r $req"
  pip install $PIP_ARGS -r "$req"
}

pip_install_pkg() {
  # pip_install_pkg <pkg>
  local pkg="$1"

  if [[ "$OFFLINE" == "1" ]]; then
    log "OFFLINE=1: skipping pip install $pkg"
    return 0
  fi

  log "pip install $pkg"
  pip install $PIP_ARGS "$pkg"
}

download_if_missing() {
  # download_if_missing <url> <dest_file>
  local url="$1" dest="$2"

  if [[ -f "$dest" ]]; then
    return 0
  fi

  if [[ "$OFFLINE" == "1" ]]; then
    log "OFFLINE=1: missing $dest but skipping download"
    return 0
  fi

  log "Downloading $(basename "$dest")"
  wget -q -O "$dest" "$url"
}

main() {
  require_cmd git
  require_cmd pip
  require_cmd python
  require_cmd wget

  mkdir -p "$CUSTOM_DIR" "$VAE_APPROX_DIR"

  # --- Sync core repo (optional update) ---
  git_sync "$COMFY_DIR" "origin/master" "https://github.com/comfyanonymous/ComfyUI.git"

  # Apply patch only if present (and do not fail hard if already applied)
  if [[ -f "$COMFY_DIR/custom_requirements.patch" ]]; then
    log "Applying custom_requirements.patch"
    patch -F 3 -p1 -d "$COMFY_DIR" < "$COMFY_DIR/custom_requirements.patch" || true
  fi

  # Install core requirements only if asked
  if [[ "$INSTALL_DEPS_ON_START" == "1" ]]; then
    pip_install_req "$COMFY_DIR/requirements.txt"
  else
    log "INSTALL_DEPS_ON_START=0: skipping core pip installs"
  fi

  # --- Custom nodes (sync + optional deps) ---
  git_sync "$CUSTOM_DIR/ComfyUI-GGUF" "origin/main" "https://github.com/city96/ComfyUI-GGUF"
  [[ "$INSTALL_DEPS_ON_START" == "1" ]] && pip_install_req "$CUSTOM_DIR/ComfyUI-GGUF/requirements.txt"

  git_sync "$CUSTOM_DIR/ComfyUI-Manager" "origin/main" "https://github.com/ltdrdata/ComfyUI-Manager.git"
  [[ "$INSTALL_DEPS_ON_START" == "1" ]] && pip_install_req "$CUSTOM_DIR/ComfyUI-Manager/requirements.txt"

  git_sync "$CUSTOM_DIR/ComfyUI-Crystools" "origin/AMD" "https://github.com/crystian/ComfyUI-Crystools.git" "AMD"
  if [[ "$INSTALL_DEPS_ON_START" == "1" ]]; then
    # Ensure your pinned numpy line exists exactly once
    if [[ -f "$CUSTOM_DIR/ComfyUI-Crystools/requirements.txt" ]] && ! grep -q '^numpy==2\.0\.2$' "$CUSTOM_DIR/ComfyUI-Crystools/requirements.txt"; then
      echo "numpy==2.0.2" >> "$CUSTOM_DIR/ComfyUI-Crystools/requirements.txt"
    fi
    pip_install_req "$CUSTOM_DIR/ComfyUI-Crystools/requirements.txt"
    pip_install_pkg "pandas==2.2.3"
  fi

  # --- EXTRA_CUSTOM_NODES ---
  if [[ -n "${EXTRA_CUSTOM_NODES:-}" ]]; then
    IFS=',;' read -ra repo_list <<< "$EXTRA_CUSTOM_NODES"
    for repo in "${repo_list[@]}"; do
      repo="$(echo "$repo" | xargs)" # trim
      [[ -z "$repo" ]] && continue
      custom_dir="$(basename "$repo")"
      custom_dir="${custom_dir%.git}"
      custom_path="$CUSTOM_DIR/$custom_dir"

      # assumes "main"
      git_sync "$custom_path" "origin/main" "$repo"
      [[ "$INSTALL_DEPS_ON_START" == "1" ]] && pip_install_req "$custom_path/requirements.txt"
    done
  fi

  # --- EXTRA_PIP_PACKAGES ---
  if [[ -n "${EXTRA_PIP_PACKAGES:-}" ]]; then
    IFS=',;' read -ra pkg_list <<< "$EXTRA_PIP_PACKAGES"
    for pkg in "${pkg_list[@]}"; do
      pkg="$(echo "$pkg" | xargs)"
      [[ -z "$pkg" ]] && continue
      pip_install_pkg "$pkg"
    done
  fi

  # --- Models downloads ---
  download_if_missing "https://github.com/madebyollin/taesd/raw/main/taesd_decoder.pth"   "$VAE_APPROX_DIR/taesd_decoder.pth"
  download_if_missing "https://github.com/madebyollin/taesd/raw/main/taesdxl_decoder.pth" "$VAE_APPROX_DIR/taesdxl_decoder.pth"

  # --- flash-attn: do NOT install at runtime unless explicitly requested ---
  if [[ "${INSTALL_FLASH_ATTN_ON_START}" == "1" ]]; then
    pip_install_pkg "flash-attn"
  fi

  log "Starting ComfyUI: python main.py $COMMANDLINE_ARGS"
  cd "$COMFY_DIR"
  exec python main.py $COMMANDLINE_ARGS
}

main "$@"


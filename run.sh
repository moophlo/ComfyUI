#!/usr/bin/env bash

set -Eeuo pipefail
[[ "${DEBUG:-0}" == "1" ]] && set -x

export FLASH_ATTENTION_TRITON_AMD_ENABLE="TRUE"
export PIP_DISABLE_PIP_VERSION_CHECK=1
export VIRTUAL_ENV=/opt/venv
export PATH="$VIRTUAL_ENV/bin:$PATH"
export PIP_NO_BUILD_ISOLATION=1
export PIP_USE_PEP517=1
hash -r
python -V
python -m pip -V

COMFY_DIR="/dockerx/ComfyUI"
CUSTOM_DIR="$COMFY_DIR/custom_nodes"
MODELS_DIR="$COMFY_DIR/models"
VAE_APPROX_DIR="$MODELS_DIR/vae_approx"

# Default args if not provided
: "${COMMANDLINE_ARGS:=--listen --front-end-version Comfy-Org/ComfyUI_frontend@latest --use-split-cross-attention --reserve-vram 6}"

# Controls (all optional)
: "${UPDATE_ON_START:=1}"                    # 1 = git fetch/reset on startup
: "${INSTALL_DEPS_ON_START:=1}"              # 1 = pip install requirements on startup
: "${INSTALL_FLASH_ATTN_ON_START:=1}"        # 1 = pip install flash-attn at runtime
: "${OFFLINE:=0}"                            # 1 = skip git/pip/wget network actions
: "${PIP_ARGS:=--timeout 180 --retries 25}"  # extra pip args

# TunableOp (PyTorch ROCm) tuning controls
# ENABLE_TUNABLEOP_TUNING: 1 = check tuning file and run offline tuning if needed
# By default we use CUSTOM_DIR (which is usually persisted) as the base dir
# for TunableOp result files, so tunings survive container rebuilds.
: "${ENABLE_TUNABLEOP_TUNING:=1}"
: "${TUNABLEOP_DIR:=$CUSTOM_DIR}"

# IMPORTANT: Use *base* filenames without a device ordinal.
# PyTorch's TunableOp will append the GPU ordinal automatically when
# insert_device_ordinal=True is used (e.g. tunableop_results0.csv).
# If you include an ordinal here (e.g. ...results0.csv) you will end up with
# confusing double-ordinal filenames like ...results00.csv.
: "${TUNABLEOP_RESULTS_FILE:=$TUNABLEOP_DIR/tunableop_results.csv}"
: "${TUNABLEOP_UNTUNED_FILE:=$TUNABLEOP_DIR/tunableop_untuned.csv}"

# Resolve the actual untuned path.
# When record-untuned is enabled, TunableOp writes tunableop_untuned<ordinal>.csv
# (e.g. tunableop_untuned0.csv) in the current working directory.
find_tunableop_untuned_file() {
  if [[ -f "$TUNABLEOP_UNTUNED_FILE" ]]; then
    echo "$TUNABLEOP_UNTUNED_FILE"
    return
  fi
  # Most deployments here are single-GPU (ordinal 0)
  if [[ -f "$TUNABLEOP_DIR/tunableop_untuned0.csv" ]]; then
    echo "$TUNABLEOP_DIR/tunableop_untuned0.csv"
    return
  fi
  echo ""
}

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
  "$VIRTUAL_ENV/bin/python" -m pip install $PIP_ARGS -r "$req"
}

pip_install_pkg() {
  # pip_install_pkg <pkg>
  local pkg="$1"

  if [[ "$OFFLINE" == "1" ]]; then
    log "OFFLINE=1: skipping pip install $pkg"
    return 0
  fi

  log "pip install $pkg"
  "$VIRTUAL_ENV/bin/python" -m pip install $PIP_ARGS $pkg
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

ensure_tunableop_tuning() {
  # Run a lightweight check to ensure the TunableOp tuning file:
  # - exists, and
  # - matches the current software configuration (validators inside the CSV).
  #
  # If the file is missing or invalid, and an untuned file is present, the helper
  # will perform offline tuning to regenerate it.

  if [[ "${ENABLE_TUNABLEOP_TUNING}" != "1" ]]; then
    log "ENABLE_TUNABLEOP_TUNING!=1: skipping TunableOp tuning check"
    return 0
  fi

  if [[ ! -f "$COMFY_DIR/tunableop_check_and_tune.py" ]]; then
    log "tunableop_check_and_tune.py not found in $COMFY_DIR; skipping TunableOp tuning"
    return 0
  fi

  log "Checking TunableOp tuning status"

  # Resolve untuned file (typically tunableop_untuned0.csv).
  untuned_path="$(find_tunableop_untuned_file)"
  if [[ -z "$untuned_path" && -f "$COMFY_DIR/tunableop_untuned0.csv" ]]; then
    log "Copying TunableOp untuned file from COMFY_DIR to persistent dir: $TUNABLEOP_DIR"
    mkdir -p "$TUNABLEOP_DIR"
    cp "$COMFY_DIR/tunableop_untuned0.csv" "$TUNABLEOP_DIR/tunableop_untuned0.csv" || true
    untuned_path="$TUNABLEOP_DIR/tunableop_untuned0.csv"
  fi
  [[ -n "$untuned_path" ]] || untuned_path="$TUNABLEOP_UNTUNED_FILE"

  TUNABLEOP_DIR="$TUNABLEOP_DIR" \
  TUNABLEOP_RESULTS_FILE="$TUNABLEOP_RESULTS_FILE" \
  TUNABLEOP_UNTUNED_FILE="$untuned_path" \
  "$VIRTUAL_ENV/bin/python" "$COMFY_DIR/tunableop_check_and_tune.py" || true
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
  # Install flash-attn in the SAME env, disabling build isolation (critical)
  if [[ "${INSTALL_FLASH_ATTN_ON_START}" == "1" ]]; then
    "$VIRTUAL_ENV/bin/python" -m pip install $PIP_ARGS --no-build-isolation flash-attn
  fi

  # If TunableOp tuning is enabled and we don't yet have an untuned file in the
  # persistent location, configure PyTorch to record untuned GEMMs during this run.
  # IMPORTANT: For the *first* run we want to record the untuned GEMMs.
  # TunableOp writes the untuned CSV into the current working directory, so we
  # start ComfyUI with CWD=$TUNABLEOP_DIR to ensure the file is persisted.
  untuned_exists="$(find_tunableop_untuned_file)"
  if [[ "${ENABLE_TUNABLEOP_TUNING}" == "1" && -z "$untuned_exists" ]]; then
    log "No TunableOp untuned file in persistent dir; enabling recording for this run"
    : "${PYTORCH_TUNABLEOP_ENABLED:=1}"
    : "${PYTORCH_TUNABLEOP_TUNING:=0}"
    : "${PYTORCH_TUNABLEOP_RECORD_UNTUNED:=1}"
    # Do NOT set PYTORCH_TUNABLEOP_FILENAME on the first run.
    # If set to a non-existent file, PyTorch will try to read it and log an error.
    unset PYTORCH_TUNABLEOP_FILENAME || true
    export PYTORCH_TUNABLEOP_ENABLED \
           PYTORCH_TUNABLEOP_TUNING \
           PYTORCH_TUNABLEOP_RECORD_UNTUNED
  fi

  # --- TunableOp tuning check & offline tuning (if configured) ---
  ensure_tunableop_tuning

  log "Starting ComfyUI: python main.py $COMMANDLINE_ARGS"

  # If we are recording untuned GEMMs, ensure CWD is the persistent dir so
  # tunableop_untuned0.csv lands there.
  if [[ "${PYTORCH_TUNABLEOP_RECORD_UNTUNED:-0}" == "1" ]]; then
    cd "$TUNABLEOP_DIR"
  else
    cd "$COMFY_DIR"
  fi

  # Start in background so PID 1 can forward signals and allow graceful shutdown
  # (important for flushing TunableOp CSVs).
  "$VIRTUAL_ENV/bin/python" "$COMFY_DIR/main.py" $COMMANDLINE_ARGS &
  CHILD=$!

  term_handler() {
    log "Received TERM/INT: forwarding to ComfyUI process group (PID $CHILD)"
    # Send TERM to the whole process group so compile_worker children exit too.
    PGID=$(ps -o pgid= -p "$CHILD" | tr -d ' ' || true)
    if [[ -n "$PGID" ]]; then
      kill -TERM -"$PGID" 2>/dev/null || true
    else
      kill -TERM "$CHILD" 2>/dev/null || true
    fi
    wait "$CHILD" 2>/dev/null || true
  }
  trap term_handler TERM INT

  wait "$CHILD"
}

main "$@"


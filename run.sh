#!/bin/bash -x

export FLASH_ATTENTION_TRITON_AMD_ENABLE="TRUE"

if [ -n "$COMMANDLINE_ARGS" ]; then
	export COMMANDLINE_ARGS=$COMMANDLINE_ARGS
else
	export COMMANDLINE_ARGS="--listen --front-end-version Comfy-Org/ComfyUI_frontend@latest --use-split-cross-attention --reserve-vram 6"
fi

# Update the main repository, patch it, and install its requirements
cd /dockerx/ComfyUI || exit
git fetch origin
git reset --hard origin/master	
patch -F 3 -p1 < custom_requirements.patch
pip install -r requirements.txt

if [ -d /dockerx/ComfyUI/custom_nodes/ComfyUI-GGUF ]; then
	cd /dockerx/ComfyUI/custom_nodes/ComfyUI-GGUF || exit
	#git pull
        git fetch origin
        git reset --hard origin/main	
        pip install -r /dockerx/ComfyUI/custom_nodes/ComfyUI-GGUF/requirements.txt
	cd - || exit
else
	git clone https://github.com/city96/ComfyUI-GGUF /dockerx/ComfyUI/custom_nodes/ComfyUI-GGUF
  pip install -r /dockerx/ComfyUI/custom_nodes/ComfyUI-GGUF/requirements.txt
fi

if [ -d /dockerx/ComfyUI/custom_nodes/ComfyUI-Manager ]; then
	cd /dockerx/ComfyUI/custom_nodes/ComfyUI-Manager || exit
	#git pull
        git fetch origin
        git reset --hard origin/main	
        pip install -r /dockerx/ComfyUI/custom_nodes/ComfyUI-Manager/requirements.txt
	cd - || exit
else
  git clone https://github.com/ltdrdata/ComfyUI-Manager.git /dockerx/ComfyUI/custom_nodes/ComfyUI-Manager
  pip install -r /dockerx/ComfyUI/custom_nodes/ComfyUI-Manager/requirements.txt
fi

if [ -d /dockerx/ComfyUI/custom_nodes/ComfyUI-Crystools ]; then
	cd /dockerx/ComfyUI/custom_nodes/ComfyUI-Crystools || exit
	#git pull
        git fetch origin
        git reset --hard origin/AMD	
        pip install -r /dockerx/ComfyUI/custom_nodes/ComfyUI-Crystools/requirements.txt
	cd - || exit
else
  git clone -b AMD https://github.com/crystian/ComfyUI-Crystools.git /dockerx/ComfyUI/custom_nodes/ComfyUI-Crystools
  echo "numpy==2.0.2" >>  /dockerx/ComfyUI/custom_nodes/ComfyUI-Crystools/requirements.txt
  pip install -r /dockerx/ComfyUI/custom_nodes/ComfyUI-Crystools/requirements.txt
  pip install --no-cache-dir --no-deps --force-reinstall "pandas==2.2.3"
fi

echo "Installing additional requirements from custom_nodes..."
# Use find to look for requirements.txt files under custom_nodes
find /dockerx/ComfyUI/custom_nodes/ -type f -name "requirements.txt" | while read req; do
    echo "Installing requirements from $req"
    pip install -r "$req"
done

# Process extra custom node repositories if provided.
# EXTRA_CUSTOM_NODES can be a comma or semicolon separated list of Git URLs.
if [ -n "$EXTRA_CUSTOM_NODES" ]; then
    mkdir -p /dockerx/ComfyUI/custom_nodes
    # Split the EXTRA_CUSTOM_NODES variable on comma and semicolon
    IFS=',;' read -ra repo_list <<< "$EXTRA_CUSTOM_NODES"
    for repo in "${repo_list[@]}"; do
        # Derive the custom node directory name from the Git URL by taking the basename and stripping .git if present.
        custom_dir=$(basename "$repo")
        custom_dir=${custom_dir%.git}
        custom_path="/dockerx/ComfyUI/custom_nodes/$custom_dir"

        if [ -d "$custom_path" ]; then
            cd "$custom_path" || exit
            git fetch origin
            git reset --hard origin/main
            [ -f requirements.txt ] && pip install -r requirements.txt
            cd - || exit
        else
            git clone "$repo" "$custom_path"
            [ -f "$custom_path/requirements.txt" ] && pip install -r "$custom_path/requirements.txt"
        fi
    done
fi

# Install extra pip packages if specified.
# EXTRA_PIP_PACKAGES can be a comma or semicolon separated list.
if [ -n "$EXTRA_PIP_PACKAGES" ]; then
    IFS=',;' read -ra pkg_list <<< "$EXTRA_PIP_PACKAGES"
    for pkg in "${pkg_list[@]}"; do
        pip install "$pkg"
    done
fi

# Download additional model files if they are not already present
mkdir -p /dockerx/ComfyUI/models/vae_approx && cd /dockerx/ComfyUI/models/vae_approx || exit
if [ ! -f taesd_decoder.pth ]; then
    wget -c https://github.com/madebyollin/taesd/raw/main/taesd_decoder.pth
fi

if [ ! -f taesdxl_decoder.pth ]; then
    wget -c https://github.com/madebyollin/taesd/raw/main/taesdxl_decoder.pth
fi
cd - || exit

pip install --no-build-isolation --no-cache-dir flash-attn

python main.py $COMMANDLINE_ARGS

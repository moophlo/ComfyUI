#!/bin/bash -x

if [ -n "$COMMANDLINE_ARGS" ]; then
	export COMMANDLINE_ARGS=$COMMANDLINE_ARGS
else
	export COMMANDLINE_ARGS="--listen --front-end-version Comfy-Org/ComfyUI_frontend@latest --use-split-cross-attention --reserve-vram 6"
fi

# Update the main repository, patch it, and install its requirements
cd /dockerx/ComfyUI
git fetch origin
git reset --hard origin/master	
patch -p1 < custom_requirements.patch
pip install -r requirements.txt

if [ -d /dockerx/ComfyUI/custom_nodes/ComfyUI-GGUF ]; then
	cd /dockerx/ComfyUI/custom_nodes/ComfyUI-GGUF
	#git pull
        git fetch origin
        git reset --hard origin/main	
        pip install -r /dockerx/ComfyUI/custom_nodes/ComfyUI-GGUF/requirements.txt
	cd -
else
	git clone https://github.com/city96/ComfyUI-GGUF /dockerx/ComfyUI/custom_nodes/ComfyUI-GGUF
  pip install -r /dockerx/ComfyUI/custom_nodes/ComfyUI-GGUF/requirements.txt
fi

if [ -d /dockerx/ComfyUI/custom_nodes/ComfyUI-Manager ]; then
	cd /dockerx/ComfyUI/custom_nodes/ComfyUI-Manager
	#git pull
        git fetch origin
        git reset --hard origin/main	
        pip install -r /dockerx/ComfyUI/custom_nodes/ComfyUI-Manager/requirements.txt
	cd -
else
  git clone https://github.com/ltdrdata/ComfyUI-Manager.git /dockerx/ComfyUI/custom_nodes/ComfyUI-Manager
  pip install -r /dockerx/ComfyUI/custom_nodes/ComfyUI-Manager/requirements.txt
fi

# If EXTRA_CUSTOM_NODES is set and not empty, process each repository
if [ -n "$EXTRA_CUSTOM_NODES" ]; then
    mkdir -p /dockerx/ComfyUI/custom_nodes
    for repo in $EXTRA_CUSTOM_NODES; do
        # Derive the custom node directory name from the Git URL.
        custom_dir=$(basename "$repo")
        custom_dir=${custom_dir%.git}
        custom_path="/dockerx/ComfyUI/custom_nodes/$custom_dir"

        if [ -d "$custom_path" ]; then
            cd "$custom_path"
            git fetch origin
            git reset --hard origin/main
            [ -f requirements.txt ] && pip install -r requirements.txt
            cd -
        else
            git clone "$repo" "$custom_path"
            [ -f "$custom_path/requirements.txt" ] && pip install -r "$custom_path/requirements.txt"
        fi
    done
fi

# Download additional model files if they are not already present
mkdir -p /dockerx/ComfyUI/models/vae_approx && cd /dockerx/ComfyUI/models/vae_approx
if [ ! -f taesd_decoder.pth ]; then
    wget -c https://github.com/madebyollin/taesd/raw/main/taesd_decoder.pth
fi

if [ ! -f taesdxl_decoder.pth ]; then
    wget -c https://github.com/madebyollin/taesd/raw/main/taesdxl_decoder.pth
fi
cd -

python main.py $COMMANDLINE_ARGS

#!/bin/bash -x

if [ -n "$COMMANDLINE_ARGS" ]; then
	export COMMANDLINE_ARGS=$COMMANDLINE_ARGS
else
	export COMMANDLINE_ARGS="--listen --front-end-version Comfy-Org/ComfyUI_frontend@latest --use-split-cross-attention --reserve-vram 6"
	#export COMMANDLINE_ARGS="--listen --force-fp32 --fp32-vae --fp32-text-enc --use-quad-cross-attention"
fi

#mv /opt/conda/envs/comfyui/lib/python3.12/site-packages/torch/lib/libMIOpen.so /opt/conda/envs/comfyui/lib/python3.12/site-packages/torch/lib/libMIOpen.so_ORIG
#cp /opt/rocm/lib/libMIOpen.so.1.0.60304 /opt/conda/envs/comfyui/lib/python3.12/site-packages/torch/lib/libMIOpen.so

cd /dockerx/ComfyUI
#git pull
git fetch origin
git reset --hard origin/master	
patch -p1 < custom_requirements.patch

if [ -d /dockerx/ComfyUI/custom_nodes/ComfyUI-GGUF ]; then
	cd /dockerx/ComfyUI/custom_nodes/ComfyUI-GGUF
	#git pull
        git fetch origin
        git reset --hard origin/main	
	cd -
else
	git clone https://github.com/city96/ComfyUI-GGUF /dockerx/ComfyUI/custom_nodes/ComfyUI-GGUF
fi

if [ -d /dockerx/ComfyUI/custom_nodes/ComfyUI_Comfyroll_CustomNodes ]; then
	cd /dockerx/ComfyUI/custom_nodes/ComfyUI_Comfyroll_CustomNodes
	#git pull
        git fetch origin
        git reset --hard origin/main	
	cd -
else
	git clone https://github.com/Suzie1/ComfyUI_Comfyroll_CustomNodes.git /dockerx/ComfyUI/custom_nodes/ComfyUI_Comfyroll_CustomNodes
fi

if [ -d /dockerx/ComfyUI/custom_nodes/ComfyUI-Manager ]; then
	cd /dockerx/ComfyUI/custom_nodes/ComfyUI-Manager
	#git pull
        git fetch origin
        git reset --hard origin/main	
	cd -
else
  	git clone https://github.com/ltdrdata/ComfyUI-Manager.git /dockerx/ComfyUI/custom_nodes/ComfyUI-Manager
fi
if [ -d /dockerx/ComfyUI/custom_nodes/AIGODLIKE-ComfyUI-Studio ]; then
	cd /dockerx/ComfyUI/custom_nodes/AIGODLIKE-ComfyUI-Studio
	#git pull
        git fetch origin
        git reset --hard origin/main	
	cd -
else
	git clone https://github.com/AIGODLIKE/AIGODLIKE-ComfyUI-Studio.git /dockerx/ComfyUI/custom_nodes/AIGODLIKE-ComfyUI-Studio
fi

mkdir -p /dockerx/ComfyUI/models/vae_approx && cd /dockerx/ComfyUI/models/vae_approx
wget -c https://github.com/madebyollin/taesd/raw/main/taesd_decoder.pth
wget -c https://github.com/madebyollin/taesd/raw/main/taesdxl_decoder.pth
cd -

#conda install -y -n comfyui -c conda-forge gcc

#conda run --no-capture-output -n comfyui python main.py $COMMANDLINE_ARGS
python main.py $COMMANDLINE_ARGS

FROM rocm/pytorch:rocm6.3.4_ubuntu24.04_py3.12_pytorch_release_2.4.0

# Set working directory for initial operations
WORKDIR /dockerx

# Update system, install necessary packages, update conda, create & configure the environment
RUN apt update && apt full-upgrade -y && \
    apt install -y bc google-perftools wget && \
    apt autoclean -y && rm -rf /var/lib/apt/lists/* && \
    conda update -y conda && \
    conda create -y --name comfyui python=3.12.7 && \
    conda clean --all -y && \
    conda init bash && \
    echo "conda activate comfyui" >> ~/.bashrc

# Clone the main repository and adjust requirements
RUN git clone https://github.com/comfyanonymous/ComfyUI.git && \
    cd ComfyUI && \
    sed -i 's/torchaudio/numpy==1.26.4/g' requirements.txt && \
    sed -i 's|^torch$|https://download.pytorch.org/whl/rocm6.2.4/torch-2.6.0%2Brocm6.2.4-cp312-cp312-manylinux_2_28_x86_64.whl|g' requirements.txt && \
    sed -i 's|^torchvision$|https://download.pytorch.org/whl/rocm6.2.4/torchvision-0.21.0%2Brocm6.2.4-cp312-cp312-linux_x86_64.whl|g' requirements.txt && \
    sed -i '1s|^|https://download.pytorch.org/whl/rocm6.2.4/torchaudio-2.6.0%2Brocm6.2.4-cp312-cp312-linux_x86_64.whl\n|' requirements.txt && \
    sed -i '1s|^|https://download.pytorch.org/whl/pytorch_triton_rocm-3.2.0-cp312-cp312-linux_x86_64.whl\n|' requirements.txt && \
    git diff requirements.txt > custom_requirements.patch

# Clone custom nodes repository
WORKDIR /dockerx/ComfyUI
#RUN git clone https://github.com/city96/ComfyUI-GGUF.git custom_nodes/ComfyUI-GGUF &&\
#    git clone https://github.com/Suzie1/ComfyUI_Comfyroll_CustomNodes.git custom_nodes/ComfyUI_Comfyroll_CustomNodes && \
#    git clone https://github.com/ltdrdata/ComfyUI-Manager.git custom_nodes/ComfyUI-Manager && \
#    git clone https://github.com/AIGODLIKE/AIGODLIKE-ComfyUI-Studio.git custom_nodes/AIGODLIKE-ComfyUI-Studio

# Configure conda channels and install Python dependencies with pip, then purge pip cache
RUN conda config --add channels defaults && \
    conda config --add channels conda-forge && \
    conda config --add channels anaconda && \
    conda config --set channel_priority strict && \
    conda run --no-capture-output -n comfyui pip install -r requirements.txt && \
    conda run --no-capture-output -n comfyui pip install onnxruntime onnxruntime-gpu evalidate && \
    #conda run --no-capture-output -n comfyui pip install -r custom_nodes/ComfyUI-GGUF/requirements.txt && \
    conda install -n comfyui -c conda-forge gcc_linux-64 libgcc-ng libstdcxx-ng piexif deepdiff evaluate matplotlib opencv diffusers && \
    conda run --no-capture-output -n comfyui pip cache purge

# Download additional model files
#RUN mkdir -p models/vae_approx && \
#    cd models/vae_approx && \
#    wget -c https://github.com/madebyollin/taesd/raw/main/taesd_decoder.pth && \
#    wget -c https://github.com/madebyollin/taesd/raw/main/taesdxl_decoder.pth

# Set working directory to the ComfyUI repository, add and prepare the entrypoint script
WORKDIR /dockerx/ComfyUI
COPY run.sh .
RUN chmod +x run.sh

ENTRYPOINT ["./run.sh"]

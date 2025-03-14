FROM rocm/pytorch:rocm6.3.4_ubuntu24.04_py3.12_pytorch_release_2.4.0

# Set working directory for initial operations
WORKDIR /dockerx

# Update system, install necessary packages, update conda, create & configure the environment
RUN apt update && apt full-upgrade -y && \
    apt install -y bc google-perftools wget && \
    apt autoclean -y && rm -rf /var/lib/apt/lists/*

# Clone the main repository and adjust requirements
RUN git clone https://github.com/comfyanonymous/ComfyUI.git && \
    cd ComfyUI && \
    sed -i 's|^torchaudio$|https://repo.radeon.com/rocm/manylinux/rocm-rel-6.3.4/torchaudio-2.4.0%2Brocm6.3.4.git69d40773-cp312-cp312-linux_x86_64.whl|g' requirements.txt && \
    sed -i 's|^torch$|https://repo.radeon.com/rocm/manylinux/rocm-rel-6.3.4/torch-2.4.0%2Brocm6.3.4.git7cecbf6d-cp312-cp312-linux_x86_64.whl|g' requirements.txt && \
    sed -i 's|^torchvision$|https://repo.radeon.com/rocm/manylinux/rocm-rel-6.3.4/torchvision-0.19.0%2Brocm6.3.4.gitfab84886-cp312-cp312-linux_x86_64.whl|g' requirements.txt && \
    sed -i '1s|^|https://repo.radeon.com/rocm/manylinux/rocm-rel-6.3.4/pytorch_triton_rocm-3.0.0%2Brocm6.3.4.git75cc27c2-cp312-cp312-linux_x86_64.whl\n|' requirements.txt && \
    git diff requirements.txt > custom_requirements.patch

# Clone custom nodes repository
WORKDIR /dockerx/ComfyUI
RUN pip install -r requirements.txt
# Set working directory to the ComfyUI repository, add and prepare the entrypoint script
COPY run.sh .
RUN chmod +x run.sh

ENTRYPOINT ["./run.sh"]

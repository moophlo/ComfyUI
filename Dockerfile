#FROM rocm/pytorch:rocm6.4_ubuntu24.04_py3.12_pytorch_release_2.6.0
FROM rocm/pytorch:rocm7.0_ubuntu24.04_py3.12_pytorch_release_2.8.0

USER root
WORKDIR /dockerx

# Clone ComfyUI and install its requirements
RUN git clone https://github.com/comfyanonymous/ComfyUI.git

# System update and base packages
RUN apt update && apt full-upgrade -y && \
    apt install -y \
      bc \
      google-perftools \
      wget \
      git \
      cmake \
      ninja-build \
      python3-dev \
      build-essential \
      hip-dev \
      rocm-dev && \
    apt autoclean -y && rm -rf /var/lib/apt/lists/*

WORKDIR /dockerx/ComfyUI
COPY custom_requirements.patch .
RUN <<'SH'
set -Eeuo pipefail
f=requirements.txt
sed -i 's/\r$//' "$f"
sed -ri 's|^torch$|https://repo.radeon.com/rocm/manylinux/rocm-rel-7.0/torch-2.8.0%2Brocm7.0.0.git64359f59-cp312-cp312-linux_x86_64.whl|' "$f"
sed -ri 's|^torchvision$|https://repo.radeon.com/rocm/manylinux/rocm-rel-7.0/torchvision-0.24.0%2Brocm7.0.0.gitf52c4f1a-cp312-cp312-linux_x86_64.whl|' "$f"
sed -ri 's|^torchaudio$|https://repo.radeon.com/rocm/manylinux/rocm-rel-7.0/torchaudio-2.8.0%2Brocm7.0.0.git6e1c7fe9-cp312-cp312-linux_x86_64.whl|' "$f"
sed -ri '/repo\.radeon\.com\/rocm\/manylinux\/rocm-rel-7\.0\/(pytorch_triton_rocm|onnxruntime_rocm|apex-|jax_rocm7_plugin|tensorflow_rocm)/d' "$f"
cat >> "$f" <<'EOF'
https://repo.radeon.com/rocm/manylinux/rocm-rel-7.0/pytorch_triton_rocm-3.4.0%2Brocm7.0.0.gitf9e5bf54-cp312-cp312-linux_x86_64.whl
https://repo.radeon.com/rocm/manylinux/rocm-rel-7.0/onnxruntime_rocm-1.22.1-cp312-cp312-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl
https://repo.radeon.com/rocm/manylinux/rocm-rel-7.0/apex-1.8.0a0%2Brocm7.0.0.git3f26640c-cp312-cp312-linux_x86_64.whl
https://repo.radeon.com/rocm/manylinux/rocm-rel-7.0/jax_rocm7_plugin-0.6.0-cp312-cp312-manylinux_2_28_x86_64.whl
https://repo.radeon.com/rocm/manylinux/rocm-rel-7.0/tensorflow_rocm-2.19.0-cp312-cp312-manylinux_2_28_x86_64.whl
flash-attn
hiredis
PyOpenGL-accelerate
sageattention
EOF
sed -ri 's|^\+([A-Za-z]+://)|\1|' "$f"
SH

RUN pip install -r requirements.txt

# Build and install ROCm Flash-Attention from source
WORKDIR /dockerx

# install flash attention
ENV FLASH_ATTENTION_TRITON_AMD_ENABLE="TRUE"

RUN git clone https://github.com/ROCm/flash-attention.git &&\ 
    cd flash-attention &&\
    git checkout main_perf &&\
    python setup.py install

# Fix permissions
RUN chown -R root:root /root

# Copy entrypoint and make executable
WORKDIR /dockerx/ComfyUI
COPY run.sh .
RUN chmod +x run.sh

ENTRYPOINT ["./run.sh"]

#FROM rocm/pytorch:rocm6.4_ubuntu24.04_py3.12_pytorch_release_2.6.0
FROM rocm/pytorch:rocm6.4.1_ubuntu24.04_py3.12_pytorch_release_2.7.1

USER root
WORKDIR /dockerx

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

# Clone ComfyUI and install its requirements
RUN git clone https://github.com/comfyanonymous/ComfyUI.git
WORKDIR /dockerx/ComfyUI
COPY custom_requirements.patch .
RUN patch -F 3 -p1 < custom_requirements.patch
RUN pip install -r requirements.txt

# Build and install ROCm Flash-Attention from source
WORKDIR /dockerx
# install triton
RUN pip install triton==3.2.0

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

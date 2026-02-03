FROM rocm/pytorch:rocm7.2_ubuntu24.04_py3.12_pytorch_release_2.9.1

USER root
WORKDIR /dockerx

RUN git clone https://github.com/comfyanonymous/ComfyUI.git

# System update and base packages
RUN apt update && \
    apt install -y \
      python3.13-full \
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

RUN set -eu; \
  f=requirements.txt; \
  # Normalize CRLF just in case
  sed -i 's/\r$//' "$f"; \
  # Exact replacements (won't hit torchsde)
  { \
    echo 'https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2/triton-3.5.1%2Brocm7.2.0.gita272dfa8-cp312-cp312-linux_x86_64.whl'; \
    echo 'https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2/jax_rocm7_pjrt-0.8.0%2Brocm7.2.0-py3-none-manylinux_2_28_x86_64.whl'; \
    echo 'https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2/jax_rocm7_plugin-0.8.0%2Brocm7.2.0-cp312-cp312-manylinux_2_28_x86_64.whl'; \
    echo 'https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2/triton_kernels-1.0.0-py3-none-any.whl'; \
    echo 'hiredis'; \
    echo 'PyOpenGL-accelerate'; \
    echo 'sageattention'; \
  } >> "$f"; \
  # Safety: if a stray '+' ever appears at start of URL line
  sed -i 's|^\+https://|https://|' "$f"

#RUN pip install flash-attn --no-build-isolation
ENV PIP_DEFAULT_TIMEOUT=180 \
    PIP_RETRIES=25 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN pip install --timeout 180 --retries 25 -r requirements.txt

# Build and install ROCm Flash-Attention from source
WORKDIR /dockerx

# Fix permissions
RUN chown -R root:root /root

# Copy entrypoint and make executable
WORKDIR /dockerx/ComfyUI
COPY run.sh .
RUN chmod +x run.sh

ENTRYPOINT ["./run.sh"]

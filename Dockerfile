FROM rocm/pytorch:rocm7.2_ubuntu24.04_py3.12_pytorch_release_2.9.1

USER root
WORKDIR /dockerx

RUN git clone https://github.com/comfyanonymous/ComfyUI.git

RUN apt update && \
    apt install -y \
      bc google-perftools wget git cmake ninja-build \
      build-essential hip-dev rocm-dev && \
    apt autoclean -y && rm -rf /var/lib/apt/lists/*

WORKDIR /dockerx/ComfyUI

ENV PIP_DEFAULT_TIMEOUT=180 \
    PIP_RETRIES=25 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH="/opt/venv/bin:$PATH"

# Hard assert we are using the venv python/pip (prints paths at build-time)
RUN /opt/venv/bin/python -V && \
    /opt/venv/bin/python -m pip -V && \
    /opt/venv/bin/python -c "import sys; print(sys.executable)" && \
    /opt/venv/bin/python -c "import torch; print(torch.__version__)"

# If requirements.txt contains flash-attn, REMOVE it (so it won't build in isolation as a dependency)
RUN sed -i '/^flash-attn(\b|==|>=|<=|~=|$)/d' requirements.txt || true

# Your appended ROCm wheels etc (keep your block)
RUN set -eu; \
  f=requirements.txt; \
  sed -i 's/\r$//' "$f"; \
  { \
    echo 'https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2/triton-3.5.1%2Brocm7.2.0.gita272dfa8-cp312-cp312-linux_x86_64.whl'; \
    echo 'https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2/jax_rocm7_pjrt-0.8.0%2Brocm7.2.0-py3-none-manylinux_2_28_x86_64.whl'; \
    echo 'https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2/jax_rocm7_plugin-0.8.0%2Brocm7.2.0-cp312-cp312-manylinux_2_28_x86_64.whl'; \
    echo 'https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2/triton_kernels-1.0.0-py3-none-any.whl'; \
    echo 'hiredis'; \
    echo 'PyOpenGL-accelerate'; \
    echo 'sageattention'; \
  } >> "$f"; \
  sed -i 's|^\+https://|https://|' "$f"

# Install requirements explicitly via the venv interpreter
RUN /opt/venv/bin/python -m pip install --timeout 180 --retries 25 -r requirements.txt

# Install flash-attn in the SAME env, disabling build isolation (critical)
RUN /opt/venv/bin/python -m pip install --no-build-isolation --timeout 180 --retries 25 flash-attn

WORKDIR /dockerx/ComfyUI
COPY run.sh .
RUN chmod +x run.sh

ENTRYPOINT ["./run.sh"]


FROM rocm/pytorch:rocm6.3.4_ubuntu24.04_py3.12_pytorch_release_2.4.0

# Set working directory for initial operations
WORKDIR /dockerx

# Update system, install necessary packages, update conda, create & configure the environment
RUN apt update && apt full-upgrade -y && \
    apt install -y bc google-perftools wget && \
    apt autoclean -y && rm -rf /var/lib/apt/lists/*

# Clone the main repository and adjust requirements
RUN git clone https://github.com/comfyanonymous/ComfyUI.git

# Clone custom nodes repository
WORKDIR /dockerx/ComfyUI
COPY custom_requirements.patch .
RUN patch -F 3 -p1 < custom_requirements.patch
RUN pip install -r requirements.txt

# Set working directory to the ComfyUI repository, add and prepare the entrypoint script
COPY run.sh .
RUN chmod +x run.sh

ENTRYPOINT ["./run.sh"]

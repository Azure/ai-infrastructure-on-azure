FROM mosaicml/llm-foundry:2.6.0_cu124-latest

ENV DEBIAN_FRONTEND=noninteractive
ARG DOCA_URL=https://linux.mellanox.com/public/repo/doca/2.9.1/ubuntu22.04/x86_64/

# Install system dependencies, DOCA, and Mellanox tools
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
        curl gnupg git wget build-essential \
        libtool m4 automake \
        ca-certificates && \
    curl ${DOCA_URL}/GPG-KEY-Mellanox.pub | gpg --dearmor -o /etc/apt/trusted.gpg.d/mellanox.gpg && \
    echo "deb [signed-by=/etc/apt/trusted.gpg.d/mellanox.gpg] ${DOCA_URL} ./" > /etc/apt/sources.list.d/doca.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        mft=4.30.1-8 doca-ofed-userspace && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Build nccl-rdma-sharp-plugins
RUN git clone --depth 1 https://github.com/Mellanox/nccl-rdma-sharp-plugins.git /opt/nccl-rdma-sharp-plugins && \
    cd /opt/nccl-rdma-sharp-plugins && \
    ./autogen.sh && \
    ./configure --with-cuda=/usr/local/cuda && \
    make -j16 && make install && \
    rm -rf /opt/nccl-rdma-sharp-plugins

# Clone LLM Foundry and install Python packages
RUN git clone --branch release/v0.18.0 --depth 1 https://github.com/mosaicml/llm-foundry.git /llm-foundry && \
    pip install -U pip && \
    pip install -e /llm-foundry[gpu] IPython

# Add NDv5 topology
RUN wget -O /etc/ndv5-topo.xml https://raw.githubusercontent.com/Azure/azhpc-images/refs/heads/master/topology/ndv5-topo.xml

# Build NCCL
RUN git clone --depth 1 https://github.com/NVIDIA/nccl.git /opt/nccl && \
    make -C /opt/nccl -j16 src.build CUDA_HOME=/usr/local/cuda && \
    make -C /opt/nccl install && \
    rm -rf /opt/nccl

# Build NCCL tests
RUN git clone --depth 1 https://github.com/NVIDIA/nccl-tests.git /opt/nccl-tests && \
    make -C /opt/nccl-tests MPI=1 \
        MPI_HOME=/usr/mpi/gcc/openmpi-4.1.7rc1 \
        CUDA_HOME=/usr/local/cuda \
        NCCL_HOME=/opt/nccl/build && \
    rm -rf /opt/nccl-tests/.git

# Set environment variables
ENV LD_LIBRARY_PATH=/usr/local/lib:/usr/mpi/gcc/openmpi-4.1.7rc1/lib:$LD_LIBRARY_PATH
ENV LD_PRELOAD=/opt/nccl/build/lib/libnccl.so

# Set a default command and healthcheck
CMD ["ipython"]
HEALTHCHECK CMD ["python3", "-c", "import torch; assert torch.cuda.is_available()"]

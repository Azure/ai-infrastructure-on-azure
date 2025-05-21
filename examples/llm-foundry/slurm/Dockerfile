FROM mosaicml/llm-foundry:2.6.0_cu124-latest
ENV DEBIAN_FRONTEND=noninteractive

ARG DOCA_URL=https://linux.mellanox.com/public/repo/doca/2.9.1/ubuntu22.04/x86_64/

RUN apt-get update -y \
 && apt-get install -y --fix-missing --allow-downgrades --allow-change-held-packages --no-install-recommends

RUN apt-get update -y \
 && apt install -y curl \
 && curl https://linux.mellanox.com/public/repo/doca/GPG-KEY-Mellanox.pub | gpg --dearmor > /etc/apt/trusted.gpg.d/GPG-KEY-Mellanox.pub \
 && echo "deb [signed-by=/etc/apt/trusted.gpg.d/GPG-KEY-Mellanox.pub] ${DOCA_URL} ./" > /etc/apt/sources.list.d/doca.list \
 && apt update \
 && apt install -y mft=4.30.1-8 \
 && apt install -y doca-ofed-userspace

WORKDIR /opt/
RUN git clone https://github.com/Mellanox/nccl-rdma-sharp-plugins.git
WORKDIR /opt/nccl-rdma-sharp-plugins
RUN ./autogen.sh
RUN ./configure --with-cuda=/usr/local/cuda
RUN make
RUN make install
ENV LD_LIBRARY_PATH=/usr/local/lib:${LD_LIBRARY_PATH}

RUN git clone --branch release/v0.18.0 https://github.com/mosaicml/llm-foundry.git /llm-foundry
WORKDIR /llm-foundry
RUN pip install -U pip
RUN pip install -e ".[gpu]"
RUN pip install IPython

WORKDIR /etc
RUN wget https://raw.githubusercontent.com/Azure/azhpc-images/refs/heads/master/topology/ndv5-topo.xml

RUN git clone https://github.com/NVIDIA/nccl /opt/nccl \
    && cd /opt/nccl \
    && make -j src.build CUDA_HOME=/usr/local/cuda \
    && make install

RUN git clone https://github.com/NVIDIA/nccl-tests.git /opt/nccl-tests \
    && cd /opt/nccl-tests \
    && make MPI=1 \
    MPI_HOME=/usr/mpi/gcc/openmpi-4.1.7rc1 \
    CUDA_HOME=/usr/local/cuda \
    NCCL_HOME=/opt/nccl/build

RUN apt install -y moreutils

RUN apt-get clean && rm -rf /var/lib/apt/lists/*
ENV LD_LIBRARY_PATH=/usr/mpi/gcc/openmpi-4.1.7rc1/lib:$LD_LIBRARY_PATH
ENV LD_PRELOAD=/opt/nccl/build/lib/libnccl.so


#    https://content.mellanox.com/hpc/hpc-x/v2.22.1rc4/hpcx-v2.22.1-gcc-doca_ofed-ubuntu22.04-cuda12-x86_64.tbz
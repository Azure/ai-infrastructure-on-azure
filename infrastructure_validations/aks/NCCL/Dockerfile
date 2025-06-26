ARG CUDA_VERSION_MINOR=12.8.1
ARG BASE_IMAGE=nvidia/cuda:${CUDA_VERSION_MINOR}-devel-ubuntu24.04
FROM ${BASE_IMAGE} AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    wget \
    curl \
    ca-certificates \
    libpci-dev \
    libibverbs-dev \
    librdmacm-dev \
    libibumad-dev \
    libboost-program-options-dev \
    libnuma-dev \
    libopenmpi-dev \
    clang \
    libomp-dev \
    bc \
    hwloc \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

# Build NCCL Tests
ENV NCCL_TESTS_VERSION=v2.14.1
RUN git clone --branch ${NCCL_TESTS_VERSION} --depth 1 https://github.com/NVIDIA/nccl-tests.git && \
    cd nccl-tests && \
    make MPI=1 MPI_HOME=/usr/lib/x86_64-linux-gnu/openmpi NVCC_GENCODE="-gencode=arch=compute_90,code=sm_90 -gencode=arch=compute_90,code=compute_90"

# Get topology files
RUN git clone --depth=1 https://github.com/Azure/azhpc-images.git /tmp/azhpc-images

# Final minimal image
FROM nvidia/cuda:${CUDA_VERSION_MINOR}-runtime-ubuntu24.04 AS final

ENV DEBIAN_FRONTEND=noninteractive
ENV AZ_NHC_ROOT=/azure-nhc

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-client \
    openssh-server \
    libnuma1 \
    libibverbs1 \
    librdmacm1 \
    libibumad3 \
    libhwloc15 \
    libboost-program-options1.83.0 \
    openmpi-bin \
    pciutils \
    net-tools \
    && rm -rf /var/lib/apt/lists/*

# SSH setup
RUN sed -i 's/[ #]\(.*StrictHostKeyChecking \).*/ \1no/g' /etc/ssh/ssh_config && \
    echo "    UserKnownHostsFile /dev/null" >> /etc/ssh/ssh_config && \
    sed -i 's/#\(StrictModes \).*/\1no/g' /etc/ssh/sshd_config && \
    sed -i "s/[ #]\(.*Port \).*/ \12222/g" /etc/ssh/ssh_config && \
    sed -i "s/#\(Port \).*/\12222/g" /etc/ssh/sshd_config && \
    mkdir -p /var/run/sshd

# Copy binaries from builder
COPY --from=builder /tmp/nccl-tests/build/ /usr/bin/
COPY --from=builder /tmp/azhpc-images/topology /etc/topology

ENTRYPOINT ["/usr/sbin/ssh", "-D"]

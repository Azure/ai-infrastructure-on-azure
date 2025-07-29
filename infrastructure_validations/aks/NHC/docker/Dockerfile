ARG CUDA_VERSION_MINOR=12.8.1
ARG BASE_IMAGE=nvidia/cuda:${CUDA_VERSION_MINOR}-devel-ubuntu24.04
FROM ${BASE_IMAGE} AS builder

LABEL maintainer="azurehpc-health-checks"

ENV DEBIAN_FRONTEND=noninteractive
ENV AZ_NHC_ROOT=/azure-nhc

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    wget \
    curl \
    ca-certificates \
    infiniband-diags \
    ibverbs-utils \
    pciutils \
    libpci-dev \
    libibverbs-dev \
    librdmacm-dev \
    libibumad-dev \
    libboost-program-options-dev \
    numactl \
    nvme-cli \
    jq \
    libnuma-dev \
    libopenmpi-dev \
    net-tools \
    openmpi-bin \
    clang \
    libomp-dev \
    sudo \
    bc \
    bats \
    hwloc \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

### ---- Build NCCL Tests ----
ENV NCCL_TESTS_VERSION=v2.14.1
RUN git clone --branch ${NCCL_TESTS_VERSION} --depth 1 https://github.com/NVIDIA/nccl-tests.git && \
    cd nccl-tests && \
    make MPI=1 MPI_HOME=/usr/lib/x86_64-linux-gnu/openmpi NVCC_GENCODE="-gencode=arch=compute_90,code=sm_90 -gencode=arch=compute_90,code=compute_90" && \
    mkdir -p ${AZ_NHC_ROOT}/bin && \
    cp -r build/* ${AZ_NHC_ROOT}/bin && \
    mkdir -p /opt/nccl-tests/build && \
    ln -s ${AZ_NHC_ROOT}/bin/all_reduce_perf /opt/nccl-tests/build/all_reduce_perf # hardcoded path in azurehpc-health-checks

### ---- Build NVBandwidth ----
ENV NV_BANDWIDTH_VERSION=0.4
RUN git clone --branch v${NV_BANDWIDTH_VERSION} --depth 1 https://github.com/NVIDIA/nvbandwidth.git && \
    cd nvbandwidth && \
    cmake -DCMAKE_CUDA_ARCHITECTURES="90" . && \
    make && \
    cp nvbandwidth ${AZ_NHC_ROOT}/bin/

### ---- Build PerfTest ----
ENV PERF_TEST_VERSION=25.04.0-0.84
ENV PERF_TEST_HASH=g97da83e
RUN mkdir -p /tmp/perftest && \
    wget -q -O - https://github.com/linux-rdma/perftest/releases/download/${PERF_TEST_VERSION}/perftest-${PERF_TEST_VERSION}.${PERF_TEST_HASH}.tar.gz | \
    tar -xz --strip-components=1 -C /tmp/perftest && \
    cd /tmp/perftest && \
    ./configure CUDA_H_PATH=/usr/local/cuda/include/cuda.h && \
    make && \
    cp ib_write_bw ${AZ_NHC_ROOT}/bin/

### ---- Build STREAM ----
RUN mkdir -p /tmp/stream && cd /tmp/stream && \
    wget https://www.cs.virginia.edu/stream/FTP/Code/stream.c && \
    echo "CC=clang\nCFLAGS=-O3 -fopenmp\n" > Makefile && \
    echo "stream: stream.c\n\t\$(CC) \$(CFLAGS) -o stream stream.c" >> Makefile && \
    make && \
    cp stream ${AZ_NHC_ROOT}/bin/

### ---- Build NHC ----
ENV NHC_VERSION=1.4.3
RUN wget https://github.com/mej/nhc/releases/download/${NHC_VERSION}/lbnl-nhc-${NHC_VERSION}.tar.xz && \
    tar -xf lbnl-nhc-${NHC_VERSION}.tar.xz && \
    cd lbnl-nhc-${NHC_VERSION} && \
    ./configure --prefix=/usr --sysconfdir=/etc --libexecdir=/usr/libexec && \
    make && make install && \
    mkdir -p ${AZ_NHC_ROOT}/conf ${AZ_NHC_ROOT}/output

### ---- Copy Topofiles from azhpc-images ----
RUN git clone --depth=1 https://github.com/Azure/azhpc-images.git /tmp/azhpc-images && \
    mkdir -p ${AZ_NHC_ROOT}/topofiles && \
    cp /tmp/azhpc-images/topology/* "${AZ_NHC_ROOT}/topofiles/" && \
    rm -rf /tmp/azhpc-images

### ---- Copy azurerhpc-health-checks files ----
RUN git clone --depth=1 https://github.com/Azure/azurehpc-health-checks.git /tmp/azurehpc-health-checks && \
    cp -r /tmp/azurehpc-health-checks/conf ${AZ_NHC_ROOT} && \
    cp -r /tmp/azurehpc-health-checks/customTests/* /etc/nhc/scripts/. && \
    rm -rf /tmp/azurehpc-health-checks

### ---- Copy Entrypoint ----
COPY aznhc_entrypoint.sh ${AZ_NHC_ROOT}/
RUN chmod +x ${AZ_NHC_ROOT}/aznhc_entrypoint.sh

ENV PATH="${AZ_NHC_ROOT}/bin:$PATH"
WORKDIR ${AZ_NHC_ROOT}
ENTRYPOINT ["./aznhc_entrypoint.sh"]

FROM ubuntu:22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    wget \
    git \
    python3 \
    python3-pip \
    ssh \
    libhwloc-dev \
    libnuma-dev \
    mpich \
    python3.10-venv \
    && rm -rf /var/lib/apt/lists/*

# Configure SSH
RUN mkdir -p /var/run/sshd && chmod 0755 /var/run/sshd
RUN mkdir -p /run/sshd && chmod 0755 /run/sshd
RUN sed -i 's/[ #]\(.*StrictHostKeyChecking \).*/ \1no/g' /etc/ssh/ssh_config && \
    echo "    UserKnownHostsFile /dev/null" >> /etc/ssh/ssh_config && \
    sed -i 's/#\(StrictModes \).*/\1no/g' /etc/ssh/sshd_config

# Clone and install MLPerf Storage benchmark
RUN cd /tmp && \
    git clone -b v2.0 https://github.com/mlcommons/storage.git mlperf-storage && \
    cd mlperf-storage && \
    python3 -m venv /opt/mlperf-storage && \
    /opt/mlperf-storage/bin/pip3 install --no-cache-dir -e .

# Fix libmpi.so link 
RUN ln -s /lib/x86_64-linux-gnu/libmpi.so /lib/x86_64-linux-gnu/libmpi.so.12

# Set working directory
WORKDIR /opt/mlperf-storage
ENV PATH="/opt/mlperf-storage/bin:$PATH"

# Default command
CMD ["/bin/bash"]
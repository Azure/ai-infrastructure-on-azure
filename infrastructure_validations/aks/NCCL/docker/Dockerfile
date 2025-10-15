ARG PYTORCH_IMAGE=nvcr.io/nvidia/pytorch:24.09-py3
FROM ${PYTORCH_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-client \
    openssh-server \
    && rm -rf /var/lib/apt/lists/*

# SSH setup
RUN sed -i 's/[ #]\(.*StrictHostKeyChecking \).*/ \1no/g' /etc/ssh/ssh_config && \
    echo "    UserKnownHostsFile /dev/null" >> /etc/ssh/ssh_config && \
    sed -i 's/#\(StrictModes \).*/\1no/g' /etc/ssh/sshd_config && \
    sed -i "s/[ #]\(.*Port \).*/ \12222/g" /etc/ssh/ssh_config && \
    sed -i "s/#\(Port \).*/\12222/g" /etc/ssh/sshd_config && \
    mkdir -p /var/run/sshd

# Get topology files
RUN git clone --depth=1 https://github.com/Azure/azhpc-images.git /tmp/azhpc-images && \
    cp -r /tmp/azhpc-images/topology /etc/. && \
    rm -rf /tmp/azhpc-images

ENTRYPOINT ["/usr/sbin/ssh", "-D"]

ARG DOTNET_SDK_VERSION=10.0
FROM mcr.microsoft.com/dotnet/sdk:${DOTNET_SDK_VERSION}

ARG DEBIAN_FRONTEND=noninteractive

# Install Node.js 20
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs

# Install Docker Engine (full DinD — daemon runs inside the workspace)
# Detect distro (debian or ubuntu) for the correct Docker apt repo
RUN apt-get update && apt-get install -y \
    ca-certificates \
    gnupg \
    iptables \
    && install -m 0755 -d /etc/apt/keyrings \
    && . /etc/os-release \
    && curl -fsSL "https://download.docker.com/linux/${ID}/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && chmod a+r /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# Install essentials
RUN apt-get update && apt-get install -y \
    git \
    curl \
    wget \
    sudo \
    unzip \
    openssh-client \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Create coder user with docker group for socket access
RUN useradd --create-home --shell /bin/bash --groups docker coder \
    && echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Copy shared scripts, extensions, and settings into the image
COPY shared/scripts/ /opt/coder/scripts/
COPY shared/extensions/ /opt/coder/extensions/
COPY shared/settings/ /opt/coder/settings/
RUN chmod +x /opt/coder/scripts/*.sh

USER coder
WORKDIR /home/coder

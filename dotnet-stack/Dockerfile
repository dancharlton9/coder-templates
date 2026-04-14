FROM mcr.microsoft.com/dotnet/sdk:9.0

# Install Node.js 20 for React frontend
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs

# Install essentials
RUN apt-get install -y \
    git \
    curl \
    wget \
    sudo \
    unzip \
    openssh-client

# Create coder user (required by Coder)
RUN useradd --create-home --shell /bin/bash coder \
    && echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER coder
WORKDIR /home/coder
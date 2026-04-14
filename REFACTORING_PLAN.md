# Coder Templates — Refactoring Plan

## Context

We have a working Coder template (Docker provider, Docker-in-Docker via socket mount) that currently lives as a flat `main.tf` + `Dockerfile`. It provisions workspaces with: multi-repo cloning, code-server with Catppuccin theme and extensions, Claude Code, JetBrains Gateway (Rider/WebStorm/DataGrip), Docker CLI, .NET SDK 9, and Node.js 20.

We want to refactor this into a shared-module repo structure so future templates (e.g. Python, Go, data-eng) can reuse the common infrastructure without copy-pasting and diverging.

## Target Repo Structure

```
coder-templates/
├── README.md
├── shared/
│   ├── docker/
│   │   └── base.Dockerfile            # Base image all templates inherit from
│   ├── scripts/
│   │   ├── bootstrap.sh               # SSH, npm path, .bashrc, Claude Code
│   │   ├── code-server-setup.sh       # Install, extensions, settings, launch
│   │   └── clone-repos.sh             # Multi-repo clone + auto-restore loop
│   ├── extensions/
│   │   ├── core.txt                   # Extensions every workspace gets
│   │   └── dotnet-angular.txt         # Stack-specific extensions
│   ├── settings/
│   │   └── code-server.json           # Default code-server settings.json
│   └── modules/
│       ├── jetbrains/
│       │   ├── main.tf                # Rider, WebStorm, DataGrip coder_app resources
│       │   └── variables.tf           # Inputs: agent_id, workspace name, owner, folder, ide versions
│       ├── code-server/
│       │   ├── main.tf                # code-server coder_app + healthcheck
│       │   └── variables.tf           # Inputs: agent_id, folder path, port
│       └── workspace-container/
│           ├── main.tf                # docker_volume, docker_image, docker_container, coder_agent
│           └── variables.tf           # Inputs: image context, env vars, startup script, extra volumes
├── templates/
│   └── dotnet-angular/
│       ├── main.tf                    # Composes shared modules + template-specific config
│       └── Dockerfile                 # FROM shared base, adds .NET SDK + Node.js
└── .gitignore
```

---

## File-by-File Specification

### 1. `shared/docker/base.Dockerfile`

Extract the stack-agnostic layers from the current Dockerfile. This image is what all template Dockerfiles inherit from.

**Content — include exactly these layers in order:**

```dockerfile
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# Core essentials
RUN apt-get update && apt-get install -y \
    git \
    curl \
    wget \
    sudo \
    unzip \
    openssh-client \
    ca-certificates \
    gnupg \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Docker CLI (client only — daemon runs on host via socket mount)
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && chmod a+r /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y docker-ce-cli docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# Create coder user with docker group for socket access
RUN groupadd -f docker \
    && useradd --create-home --shell /bin/bash --groups docker coder \
    && echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER coder
WORKDIR /home/coder
```

**Notes:**
- Uses `ubuntu:24.04` as the universal base rather than a stack-specific SDK image. Template Dockerfiles that need a specific SDK base (like `mcr.microsoft.com/dotnet/sdk:9.0`) will NOT use `FROM base` — instead they'll repeat the common setup. See the note in file 9 below for the recommended pattern.
- Actually, the cleaner approach: template Dockerfiles use their own SDK base image and COPY scripts/install logic from the base. But given Coder builds the Dockerfile from `path.module`, the simplest approach is a **multi-stage build** where the base.Dockerfile is used as a reference/documentation, and each template Dockerfile is self-contained but follows the same pattern. See file 9 for the concrete approach.
- The real value of `base.Dockerfile` is as the **canonical reference** for what every workspace needs. Templates that use a non-Ubuntu base (like the .NET SDK image which is Debian) should adapt the Docker commands accordingly (e.g. use `debian` instead of `ubuntu` in the Docker apt repo URL, and use `VERSION_CODENAME` which works on both).

### 2. `shared/scripts/bootstrap.sh`

This runs at the start of every workspace's startup script. It handles SSH, PATH, and Claude Code.

**Content:**

```bash
#!/bin/bash
# bootstrap.sh — Run at the start of every workspace startup.
# Handles SSH known hosts, npm global path, and Claude Code installation.

# ── SSH / Git setup ───────────────────────────────────────────────────────────
mkdir -p ~/.ssh
ssh-keyscan -t ed25519 github.com >> ~/.ssh/known_hosts 2>/dev/null

# ── npm global path (persistent across terminals) ─────────────────────────────
mkdir -p ~/.npm-global
npm config set prefix '~/.npm-global'
export PATH=~/.npm-global/bin:$PATH
grep -q '.npm-global/bin' ~/.bashrc 2>/dev/null || \
  echo 'export PATH=~/.npm-global/bin:$PATH' >> ~/.bashrc

# ── Claude Code ───────────────────────────────────────────────────────────────
if ! command -v claude &> /dev/null; then
  npm install -g @anthropic-ai/claude-code
fi
```

**Notes:**
- Must be sourced (`. /opt/coder/scripts/bootstrap.sh`) not executed, so the `export PATH` takes effect in the calling shell.
- Idempotent — safe to run on every restart.

### 3. `shared/scripts/code-server-setup.sh`

Installs code-server, reads extension lists, applies settings, and launches.

**Content:**

```bash
#!/bin/bash
# code-server-setup.sh — Install code-server, extensions, settings, and launch.
#
# Usage: /opt/coder/scripts/code-server-setup.sh [extension_file ...] 
#
# Arguments:
#   extension_file  — Path(s) to text files containing one extension ID per line.
#                     Lines starting with # are ignored. Multiple files are merged.
#                     The core extensions file is always loaded automatically.
#
# Environment:
#   CODE_SERVER_PORT     — Port to listen on (default: 13337)
#   CODE_SERVER_FOLDER   — Folder to open (default: /home/coder/projects)
#   SETTINGS_SOURCE      — Path to settings.json template (default: /opt/coder/settings/code-server.json)

PORT="${CODE_SERVER_PORT:-13337}"
FOLDER="${CODE_SERVER_FOLDER:-/home/coder/projects}"
SETTINGS_SOURCE="${SETTINGS_SOURCE:-/opt/coder/settings/code-server.json}"
CORE_EXTENSIONS="/opt/coder/extensions/core.txt"

# ── Install code-server ───────────────────────────────────────────────────────
if ! command -v code-server &> /dev/null; then
  curl -fsSL https://code-server.dev/install.sh | sh
fi

# ── Install extensions ────────────────────────────────────────────────────────
# Always load core extensions, then any additional files passed as arguments
EXTENSION_FILES=("$CORE_EXTENSIONS")
for f in "$@"; do
  [ -f "$f" ] && EXTENSION_FILES+=("$f")
done

for ext_file in "${EXTENSION_FILES[@]}"; do
  [ -f "$ext_file" ] || continue
  while IFS= read -r ext || [ -n "$ext" ]; do
    ext=$(echo "$ext" | xargs)  # trim whitespace
    [[ -z "$ext" || "$ext" == \#* ]] && continue
    code-server --install-extension "$ext" || true
  done < "$ext_file"
done

# ── Settings ──────────────────────────────────────────────────────────────────
# Only write once — won't overwrite manual changes made inside code-server
SETTINGS_DIR=~/.local/share/code-server/User
SETTINGS_FILE="$SETTINGS_DIR/settings.json"
if [ ! -f "$SETTINGS_FILE" ] && [ -f "$SETTINGS_SOURCE" ]; then
  mkdir -p "$SETTINGS_DIR"
  cp "$SETTINGS_SOURCE" "$SETTINGS_FILE"
fi

# ── Launch ────────────────────────────────────────────────────────────────────
code-server --auth none --port "$PORT" --host 0.0.0.0 &
```

### 4. `shared/scripts/clone-repos.sh`

Multi-repo clone loop with auto-restore.

**Content:**

```bash
#!/bin/bash
# clone-repos.sh — Clone comma-separated repos into ~/projects/<name>.
# After cloning, auto-detects and runs restore commands for known project types.
#
# Usage: /opt/coder/scripts/clone-repos.sh "git@github.com:org/repo1.git,git@github.com:org/repo2.git"

REPOS_CSV="$1"
PROJECTS_DIR=~/projects

[ -z "$REPOS_CSV" ] && echo "No repositories specified." && exit 0

mkdir -p "$PROJECTS_DIR"

IFS=',' read -ra REPOS <<< "$REPOS_CSV"
for REPO_URL in "${REPOS[@]}"; do
  REPO_URL=$(echo "$REPO_URL" | xargs)  # trim whitespace
  [ -z "$REPO_URL" ] && continue

  # Extract repo name: git@github.com:org/my-repo.git → my-repo
  REPO_NAME=$(basename "$REPO_URL" .git)
  REPO_DIR="$PROJECTS_DIR/$REPO_NAME"

  if [ ! -d "$REPO_DIR/.git" ]; then
    echo "Cloning $REPO_URL into $REPO_DIR..."
    git clone "$REPO_URL" "$REPO_DIR" || { echo "WARNING: Failed to clone $REPO_URL"; continue; }
  fi

  # ── Auto-restore by project type ──────────────────────────────────────────

  # .NET
  if ls "$REPO_DIR"/*.sln 1>/dev/null 2>&1; then
    echo "Restoring .NET packages for $REPO_NAME..."
    dotnet restore "$REPO_DIR" || true
  fi

  # Node.js
  if [ -f "$REPO_DIR/package.json" ]; then
    echo "Installing npm packages for $REPO_NAME..."
    (cd "$REPO_DIR" && npm install) || true
  fi

  # Python
  if [ -f "$REPO_DIR/requirements.txt" ]; then
    echo "Installing Python packages for $REPO_NAME..."
    (cd "$REPO_DIR" && pip install -r requirements.txt --break-system-packages) || true
  fi

  # Go
  if [ -f "$REPO_DIR/go.mod" ]; then
    echo "Downloading Go modules for $REPO_NAME..."
    (cd "$REPO_DIR" && go mod download) || true
  fi
done
```

### 5. `shared/extensions/core.txt`

Extensions installed in every workspace regardless of stack.

**Content:**

```
# Theme & icons
Catppuccin.catppuccin-vsc
Catppuccin.catppuccin-vsc-icons

# Docker
ms-azuretools.vscode-docker

# General productivity
eamodio.gitlens
EditorConfig.EditorConfig
christian-kohler.path-intellisense
formulahendry.auto-rename-tag
usernamehw.errorlens
esbenp.prettier-vscode
```

### 6. `shared/extensions/dotnet-angular.txt`

Stack-specific extensions for the .NET + Angular template.

**Content:**

```
# C# / .NET
muhammad-sammy.csharp

# Angular / TypeScript
Angular.ng-template
dbaeumer.vscode-eslint
```

**Notes:**
- Future templates create their own extension files, e.g. `python-react.txt`, `go.txt`, etc.

### 7. `shared/settings/code-server.json`

Default code-server settings. Written once on first workspace creation.

**Content:**

```json
{
  "workbench.colorTheme": "Catppuccin Mocha",
  "workbench.iconTheme": "catppuccin-mocha",
  "editor.fontSize": 14,
  "editor.formatOnSave": true,
  "editor.tabSize": 2,
  "editor.bracketPairColorization.enabled": true,
  "editor.guides.bracketPairs": true,
  "editor.minimap.enabled": false,
  "terminal.integrated.defaultProfile.linux": "bash"
}
```

### 8. `shared/modules/jetbrains/`

Terraform module that creates JetBrains Gateway app resources.

**`shared/modules/jetbrains/variables.tf`:**

```hcl
variable "agent_id" {
  type        = string
  description = "The coder_agent ID to attach apps to"
}

variable "workspace_name" {
  type        = string
  description = "Coder workspace name"
}

variable "owner_name" {
  type        = string
  description = "Coder workspace owner name"
}

variable "folder" {
  type        = string
  description = "Default folder to open in the IDE"
  default     = "/home/coder/projects"
}

variable "ides" {
  type = map(object({
    display_name     = string
    icon             = string
    ide_product_code = string
    ide_build_number = string
  }))
  description = "Map of JetBrains IDEs to create apps for"
  default = {
    rider = {
      display_name     = "Rider"
      icon             = "/icon/rider.svg"
      ide_product_code = "RD"
      ide_build_number = "243.22562.250"
    }
    webstorm = {
      display_name     = "WebStorm"
      icon             = "/icon/webstorm.svg"
      ide_product_code = "WS"
      ide_build_number = "243.22562.222"
    }
    datagrip = {
      display_name     = "DataGrip"
      icon             = "/icon/datagrip.svg"
      ide_product_code = "DB"
      ide_build_number = "243.22562.170"
    }
  }
}
```

**`shared/modules/jetbrains/main.tf`:**

```hcl
resource "coder_app" "jetbrains" {
  for_each = var.ides

  agent_id     = var.agent_id
  slug         = each.key
  display_name = each.value.display_name
  icon         = each.value.icon
  url          = "jetbrains-gateway://connect#type=coder&workspace=${var.workspace_name}&owner=${var.owner_name}&folder=${var.folder}&ide_product_code=${each.value.ide_product_code}&ide_build_number=${each.value.ide_build_number}"
  external     = true
}
```

**Notes:**
- Uses `for_each` over a map so templates can pick which IDEs they want by overriding the `ides` variable, or just use the defaults to get all three.
- Build numbers are centralised here — update once, all templates pick it up.

### 9. `shared/modules/code-server/`

Terraform module for the code-server coder_app resource.

**`shared/modules/code-server/variables.tf`:**

```hcl
variable "agent_id" {
  type        = string
  description = "The coder_agent ID to attach the app to"
}

variable "folder" {
  type        = string
  description = "Default folder to open"
  default     = "/home/coder/projects"
}

variable "port" {
  type        = number
  description = "Port code-server listens on"
  default     = 13337
}
```

**`shared/modules/code-server/main.tf`:**

```hcl
resource "coder_app" "code_server" {
  agent_id     = var.agent_id
  slug         = "code-server"
  display_name = "VS Code"
  url          = "http://localhost:${var.port}/?folder=${var.folder}"
  icon         = "/icon/code.svg"
  subdomain    = false

  healthcheck {
    url       = "http://localhost:${var.port}/healthz"
    interval  = 5
    threshold = 15
  }
}
```

### 10. `shared/modules/workspace-container/`

Terraform module that encapsulates the docker_volume, docker_image, docker_container, and coder_agent resources — the boilerplate every template needs.

**`shared/modules/workspace-container/variables.tf`:**

```hcl
variable "workspace_id" {
  type = string
}

variable "workspace_name" {
  type = string
}

variable "workspace_start_count" {
  type = number
}

variable "owner_name" {
  type = string
}

variable "owner_full_name" {
  type = string
}

variable "owner_email" {
  type = string
}

variable "arch" {
  type = string
}

variable "image_context" {
  type        = string
  description = "Path to the directory containing the Dockerfile"
}

variable "startup_script" {
  type        = string
  description = "The full startup script for the agent"
}

variable "extra_env" {
  type        = map(string)
  description = "Additional environment variables for the agent"
  default     = {}
}

variable "docker_socket" {
  type        = bool
  description = "Whether to mount the Docker socket into the workspace"
  default     = true
}
```

**`shared/modules/workspace-container/main.tf`:**

```hcl
resource "docker_volume" "home_volume" {
  name = "coder-${var.workspace_id}-home"
  lifecycle {
    ignore_changes = all
  }
}

resource "coder_agent" "main" {
  os   = "linux"
  arch = var.arch

  env = merge({
    GIT_AUTHOR_NAME     = var.owner_full_name
    GIT_AUTHOR_EMAIL    = var.owner_email
    GIT_COMMITTER_NAME  = var.owner_full_name
    GIT_COMMITTER_EMAIL = var.owner_email
    PATH                = "/home/coder/.npm-global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  }, var.extra_env)

  startup_script = var.startup_script
}

resource "docker_image" "workspace" {
  name = "coder-workspace-${var.workspace_id}"
  build {
    context = var.image_context
  }
  triggers = {
    dockerfile = filesha256("${var.image_context}/Dockerfile")
  }
  keep_locally = true
}

resource "docker_container" "workspace" {
  count = var.workspace_start_count

  name  = "coder-${var.owner_name}-${var.workspace_name}"
  image = docker_image.workspace.image_id

  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
  ]

  command = [
    "sh", "-c",
    coder_agent.main.init_script
  ]

  volumes {
    volume_name    = docker_volume.home_volume.name
    container_path = "/home/coder"
    read_only      = false
  }

  dynamic "volumes" {
    for_each = var.docker_socket ? [1] : []
    content {
      host_path      = "/var/run/docker.sock"
      container_path = "/var/run/docker.sock"
      read_only      = false
    }
  }

  capabilities {
    add = ["SYS_PTRACE"]
  }

  must_run = true
}
```

**`shared/modules/workspace-container/outputs.tf`:**

```hcl
output "agent_id" {
  value = coder_agent.main.id
}
```

### 11. `templates/dotnet-angular/Dockerfile`

The stack-specific Dockerfile. Since Coder builds the Dockerfile from `path.module` (the template directory), and Terraform modules can't easily share Docker build contexts across directories, each template Dockerfile is **self-contained** but follows the pattern established by `shared/docker/base.Dockerfile`.

The shared scripts and extension files are **COPYed into the image** from the shared directory. This is the key mechanism: the template's Docker build context must include the shared files. The template's `main.tf` achieves this by setting the build context or by the repo structure making `shared/` accessible.

**IMPORTANT:** Because Coder's Docker provider builds from `path.module` (which is `templates/dotnet-angular/`), the build context won't include `shared/` by default. There are two solutions:

**Option A (Recommended): Set build context to repo root.** In `main.tf`, set the Docker image build context to the repo root and specify the Dockerfile path explicitly:

```hcl
resource "docker_image" "workspace" {
  name = "coder-workspace-${var.workspace_id}"
  build {
    context    = "${path.module}/../.."     # repo root
    dockerfile = "templates/dotnet-angular/Dockerfile"
  }
}
```

However, this means the workspace-container module needs to accept `dockerfile` as a variable too. Add to `shared/modules/workspace-container/variables.tf`:

```hcl
variable "dockerfile" {
  type        = string
  description = "Path to Dockerfile relative to image_context"
  default     = "Dockerfile"
}
```

And update the build block in `shared/modules/workspace-container/main.tf`:

```hcl
resource "docker_image" "workspace" {
  name = "coder-workspace-${var.workspace_id}"
  build {
    context    = var.image_context
    dockerfile = var.dockerfile
  }
  triggers = {
    dockerfile = filesha256("${var.image_context}/${var.dockerfile}")
  }
  keep_locally = true
}
```

**Option B: Symlink shared/ into each template directory.** Each template has a `shared` symlink → `../../shared`. Simpler but fragile.

**Go with Option A.**

**`templates/dotnet-angular/Dockerfile` content:**

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:9.0

ARG DEBIAN_FRONTEND=noninteractive

# Install Node.js 20
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs

# Install Docker CLI (client only — daemon runs on host via socket mount)
RUN apt-get update && apt-get install -y \
    ca-certificates \
    gnupg \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && chmod a+r /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y docker-ce-cli docker-compose-plugin \
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
RUN groupadd -f docker \
    && useradd --create-home --shell /bin/bash --groups docker coder \
    && echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Copy shared scripts, extensions, and settings into the image
COPY shared/scripts/ /opt/coder/scripts/
COPY shared/extensions/ /opt/coder/extensions/
COPY shared/settings/ /opt/coder/settings/
RUN chmod +x /opt/coder/scripts/*.sh

USER coder
WORKDIR /home/coder
```

**Notes:**
- The COPY commands work because the build context is the repo root (Option A).
- Stack-specific extensions are also in `shared/extensions/` — the startup script passes the right file.

### 12. `templates/dotnet-angular/main.tf`

This is the main template file that composes everything.

**Content:**

```hcl
terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

provider "coder" {}
provider "docker" {}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# ── Parameters ────────────────────────────────────────────────────────────────

data "coder_parameter" "repos" {
  name         = "Repositories"
  display_name = "Repositories"
  description  = "Comma-separated SSH git URLs (e.g. git@github.com:org/api.git,git@github.com:org/frontend.git)"
  type         = "string"
  mutable      = false
  default      = "git@github.com:dancharlton9/"
}

data "coder_parameter" "dotnet_port" {
  name         = "API Port"
  display_name = ".NET API Port"
  type         = "number"
  default      = "5000"
  mutable      = true
}

data "coder_parameter" "frontend_port" {
  name         = "Frontend Port"
  display_name = "Frontend Dev Server Port"
  type         = "number"
  default      = "5173"
  mutable      = true
}

# ── Workspace container (agent, volume, image, container) ─────────────────────

module "workspace" {
  source = "../../shared/modules/workspace-container"

  workspace_id          = data.coder_workspace.me.id
  workspace_name        = data.coder_workspace.me.name
  workspace_start_count = data.coder_workspace.me.start_count
  owner_name            = data.coder_workspace_owner.me.name
  owner_full_name       = data.coder_workspace_owner.me.full_name
  owner_email           = data.coder_workspace_owner.me.email
  arch                  = data.coder_provisioner.me.arch
  image_context         = "${path.module}/../.."
  dockerfile            = "templates/dotnet-angular/Dockerfile"
  docker_socket         = true

  startup_script = <<-EOF
    # Shared bootstrap (SSH, PATH, Claude Code)
    . /opt/coder/scripts/bootstrap.sh

    # code-server with core + stack-specific extensions
    /opt/coder/scripts/code-server-setup.sh /opt/coder/extensions/dotnet-angular.txt

    # Clone repositories
    /opt/coder/scripts/clone-repos.sh "${data.coder_parameter.repos.value}"
  EOF
}

# ── code-server app ───────────────────────────────────────────────────────────

module "code_server" {
  source   = "../../shared/modules/code-server"
  agent_id = module.workspace.agent_id
}

# ── JetBrains Gateway ─────────────────────────────────────────────────────────

module "jetbrains" {
  source         = "../../shared/modules/jetbrains"
  agent_id       = module.workspace.agent_id
  workspace_name = data.coder_workspace.me.name
  owner_name     = data.coder_workspace_owner.me.name
}

# ── Port forwards ─────────────────────────────────────────────────────────────

resource "coder_app" "api" {
  agent_id     = module.workspace.agent_id
  slug         = "api"
  display_name = ".NET API"
  url          = "http://localhost:${data.coder_parameter.dotnet_port.value}"
  icon         = "/icon/dotnet.svg"
  subdomain    = false
  share        = "owner"
}

resource "coder_app" "frontend" {
  agent_id     = module.workspace.agent_id
  slug         = "frontend"
  display_name = "Frontend"
  url          = "http://localhost:${data.coder_parameter.frontend_port.value}"
  icon         = "/icon/nodejs.svg"
  subdomain    = false
  share        = "owner"
}
```

**Notes:**
- The startup script is now just 3 lines — it calls the shared scripts and passes template-specific config (the extension file path and the repos parameter).
- Port forward `coder_app` resources stay in the template because they're stack-specific.

### 13. `README.md`

Write a README covering:

- Repo structure overview
- How to create a new template (copy `templates/dotnet-angular/`, modify Dockerfile and main.tf)
- How shared scripts work (copied into image at `/opt/coder/scripts/`)
- How to add extensions (add a `.txt` file to `shared/extensions/`, reference it in startup script)
- How to update JetBrains build numbers (edit defaults in `shared/modules/jetbrains/variables.tf`)
- How to update code-server settings (edit `shared/settings/code-server.json`)
- Prerequisites: JetBrains Gateway + Coder plugin on local machine

### 14. `.gitignore`

```
.terraform/
*.tfstate
*.tfstate.backup
*.tfvars
.terraform.lock.hcl
```

---

## Execution Order

When running this with Claude Code, execute in this order to avoid dependency issues:

1. Create the directory structure first: `mkdir -p shared/{docker,scripts,extensions,settings,modules/{jetbrains,code-server,workspace-container}} templates/dotnet-angular`
2. Create `shared/docker/base.Dockerfile` (file 1)
3. Create `shared/scripts/bootstrap.sh` (file 2)
4. Create `shared/scripts/code-server-setup.sh` (file 3)
5. Create `shared/scripts/clone-repos.sh` (file 4)
6. Create `shared/extensions/core.txt` (file 5)
7. Create `shared/extensions/dotnet-angular.txt` (file 6)
8. Create `shared/settings/code-server.json` (file 7)
9. Create `shared/modules/jetbrains/variables.tf` and `main.tf` (file 8)
10. Create `shared/modules/code-server/variables.tf` and `main.tf` (file 9)
11. Create `shared/modules/workspace-container/variables.tf`, `main.tf`, and `outputs.tf` (file 10)
12. Create `templates/dotnet-angular/Dockerfile` (file 11)
13. Create `templates/dotnet-angular/main.tf` (file 12)
14. Create `README.md` (file 13)
15. Create `.gitignore` (file 14)

## Verification

After all files are created, verify:

1. `cd templates/dotnet-angular && terraform init` — should resolve all modules
2. `terraform validate` — should pass with no errors
3. Check that the Dockerfile COPY paths align with the repo-root build context
4. Push to your coder-templates repo and create a new template in Coder pointing at `templates/dotnet-angular/`

## Creating a New Template (Example: Python + React)

To validate the architecture works, here's what creating a second template looks like:

1. `mkdir templates/python-react`
2. Create `shared/extensions/python-react.txt` with Python/React extensions
3. Create `templates/python-react/Dockerfile` — based on `python:3.12`, same pattern as dotnet-angular but with Python instead of .NET
4. Create `templates/python-react/main.tf` — same structure, different parameters (no dotnet_port, add a python port), different extension file in startup script
5. Push, create template in Coder — done.

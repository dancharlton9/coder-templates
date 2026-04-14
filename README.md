# coder-templates

Workspace templates for [Coder](https://coder.com) — a self-hosted remote development environment platform. These templates are used to provision Docker-based workspaces accessible from any device (desktop, iPad, etc.) via browser or native IDE clients.

## Infrastructure

- **Coder** running as a Docker container on a Proxmox homelab
- **Workspaces** provisioned as Docker containers on the same host
- **Remote access** via Twingate (zero-trust network access)
- **Editor access** via code-server (browser-based VS Code), native VS Code, or JetBrains Gateway

## Repository Structure

```
coder-templates/
├── shared/
│   ├── docker/
│   │   └── base.Dockerfile            # Base image reference for all templates
│   ├── scripts/
│   │   ├── bootstrap.sh               # SSH, npm path, .bashrc, Claude Code
│   │   ├── code-server-setup.sh       # Install, extensions, settings, launch
│   │   └── clone-repos.sh             # Multi-repo clone + auto-restore
│   ├── extensions/
│   │   ├── core.txt                   # Extensions every workspace gets
│   │   └── dotnet-angular.txt         # Stack-specific extensions
│   ├── settings/
│   │   └── code-server.json           # Default code-server settings.json
│   └── modules/
│       ├── jetbrains/                 # JetBrains Gateway app resources
│       ├── code-server/               # code-server app + healthcheck
│       └── workspace-container/       # docker_volume, docker_image, docker_container, coder_agent
├── templates/
│   └── dotnet-angular/
│       ├── main.tf                    # Composes shared modules + template-specific config
│       └── Dockerfile                 # FROM .NET SDK, adds Node.js
└── .gitignore
```

## How It Works

### Shared Scripts

Scripts in `shared/scripts/` are COPYed into each template's Docker image at `/opt/coder/scripts/` during the build. Each template's Dockerfile copies them from the repo root (the Docker build context is set to the repo root via Option A in the Terraform module).

- **`bootstrap.sh`** — Sourced (not executed) at workspace startup. Sets up SSH known hosts, npm global path, and installs Claude Code.
- **`code-server-setup.sh`** — Installs code-server, reads extension lists, applies settings, and launches. Pass additional extension files as arguments.
- **`clone-repos.sh`** — Clones comma-separated git URLs into `~/projects/<name>` and auto-restores packages (.NET, Node.js, Python, Go).

### Shared Modules

Terraform modules in `shared/modules/` encapsulate reusable infrastructure:

- **`workspace-container`** — The core module. Creates the Docker volume, agent, image, and container. Every template uses this.
- **`code-server`** — Registers the code-server `coder_app` with healthcheck.
- **`jetbrains`** — Registers JetBrains Gateway apps (Rider, WebStorm, DataGrip by default). Uses `for_each` so templates can override which IDEs to include.

### Extensions

Extension lists live in `shared/extensions/` as plain text files (one extension ID per line, `#` for comments). `core.txt` is always installed; stack-specific files are passed as arguments to `code-server-setup.sh`.

## Templates

### `dotnet-angular`

A workspace for .NET + Angular/TypeScript projects.

**Includes:**
- .NET SDK 9.0
- Node.js 20
- Docker CLI (client only — host socket mounted)
- code-server with Catppuccin theme
- Claude Code CLI
- JetBrains Gateway (Rider, WebStorm, DataGrip)

**Parameters:**
- Repositories — comma-separated SSH git URLs
- .NET API Port (default: 5000)
- Frontend Dev Server Port (default: 5173)

**Exposed apps:**
- VS Code (code-server)
- .NET API — proxied port forward
- Frontend — proxied port forward
- Rider / WebStorm / DataGrip via JetBrains Gateway

## Creating a New Template

1. Create a new directory: `mkdir templates/my-stack`
2. Create a stack-specific extension file: `shared/extensions/my-stack.txt`
3. Create `templates/my-stack/Dockerfile` — use the appropriate SDK base image, follow the same pattern as `dotnet-angular`
4. Create `templates/my-stack/main.tf` — compose the shared modules, pass template-specific config
5. Push to GitHub and create the template in Coder: `coder templates create my-stack --directory ./templates/my-stack`

## Updating Shared Config

- **JetBrains build numbers** — Edit defaults in `shared/modules/jetbrains/variables.tf`
- **code-server settings** — Edit `shared/settings/code-server.json`
- **Core extensions** — Edit `shared/extensions/core.txt`

## Usage

### Prerequisites

- [Coder CLI](https://coder.com/docs/install) installed and authenticated
- JetBrains Gateway + Coder plugin installed on your local machine (for JetBrains IDEs)

### Deploy or update a template

Use the push script, which bundles `shared/` into the template directory before uploading:

```bash
./push-template.sh dotnet-angular
```

The script copies `shared/` into the template dir, runs `coder templates push`, then cleans up the copy automatically.

### Create a workspace

From the Coder dashboard, select the template, fill in parameters, and click **Create Workspace**.

## First-time Setup

After a workspace is created for the first time, authenticate Claude Code:

```bash
claude login
```

The auth token is stored in `~/.claude/` on the persistent home volume and survives workspace restarts.

## SSH / Git Authentication

Workspaces use an SSH key at `/home/coder/.ssh/id_ed25519` for Git operations. To set up on a fresh workspace:

```bash
ssh-keygen -t ed25519 -C "coder-homelab" -f ~/.ssh/id_ed25519 -N ""
cat ~/.ssh/id_ed25519.pub  # add this to GitHub SSH keys
ssh -T git@github.com      # verify
```

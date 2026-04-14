# coder-templates

Workspace templates for [Coder](https://coder.com) — a self-hosted remote development environment platform. These templates are used to provision Docker-based workspaces accessible from any device (desktop, iPad, etc.) via browser or native IDE clients.

## Infrastructure

- **Coder** running as a Docker container on a Proxmox homelab
- **Workspaces** provisioned as Docker containers on the same host
- **Remote access** via Twingate (zero-trust network access)
- **Editor access** via code-server (browser-based VS Code), native VS Code, or JetBrains Gateway

## Templates

### `dotnet-stack`

A general-purpose workspace template for .NET + React projects.

**Includes:**
- .NET SDK 9.0
- Node.js 20
- Git
- Claude Code CLI (`claude`)
- Persistent home volume (survives workspace restarts)

**Parameters prompted at workspace creation:**
- Repository — dropdown of known repos to clone
- API Port — .NET backend port (default: 5000)
- Frontend Port — React dev server port (default: 5173)

**Exposed apps:**
- VS Code (code-server) — browser-based editor
- .NET API — proxied port forward to running backend
- Frontend — proxied port forward to Vite dev server

## Usage

### Prerequisites

- [Coder CLI](https://coder.com/docs/install) installed
- Authenticated against your Coder instance:

```bash
coder login https://your-coder-instance.domain.com
```

### Deploy a template

```bash
coder templates create dotnet-stack --directory ./dotnet-stack
```

### Update an existing template

```bash
coder templates push dotnet-stack --directory ./dotnet-stack
```

### Create a workspace

From the Coder dashboard, select the template, choose a repository from the dropdown, and click **Create Workspace**.

## First-time setup per workspace

After a workspace is created for the first time, authenticate Claude Code against your Anthropic subscription:

```bash
claude login
```

The auth token is stored in `~/.claude/` on the persistent home volume and will survive workspace restarts.

## SSH / Git authentication

Workspaces use an SSH key stored at `/home/coder/.ssh/id_ed25519` for Git operations. The corresponding public key is registered as a deploy key on GitHub.

To set up on a fresh Coder container:

```bash
ssh-keygen -t ed25519 -C "coder-homelab" -f ~/.ssh/id_ed25519 -N ""
cat ~/.ssh/id_ed25519.pub  # add this to GitHub SSH keys
ssh -T git@github.com      # verify
```

## Adding a new template

1. Create a new directory under the repo root
2. Add `main.tf` and `Dockerfile`
3. Push to GitHub
4. Deploy via `coder templates create <name> --directory ./<name>`

## Repository structure

```
coder-templates/
  dotnet-stack/
    main.tf       # Terraform template defining the workspace
    Dockerfile    # Container image for the workspace
  README.md
```
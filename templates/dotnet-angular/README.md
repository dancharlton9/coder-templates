# .NET + Angular Workspace

A development workspace pre-configured for .NET and Angular/TypeScript projects.

## What's Included

| Tool | Version |
|------|---------|
| .NET SDK | 9.0 |
| Node.js | 20 |
| Docker CLI | Latest (host socket mounted) |
| Claude Code | Latest |

## Editors

- **VS Code** — browser-based via code-server (Catppuccin Mocha theme, extensions pre-installed)
- **Rider** — via JetBrains Gateway
- **WebStorm** — via JetBrains Gateway
- **DataGrip** — via JetBrains Gateway

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| Repositories | Comma-separated SSH git URLs to clone | — |
| .NET API Port | Port for the .NET backend | 5000 |
| Frontend Port | Port for the dev server (Vite/ng serve) | 5173 |

## First-Time Setup

After your first workspace creation, authenticate Claude Code:

```bash
claude login
```

If you need to set up SSH keys for Git:

```bash
ssh-keygen -t ed25519 -C "coder-homelab" -f ~/.ssh/id_ed25519 -N ""
cat ~/.ssh/id_ed25519.pub  # add this to GitHub SSH keys
```

## Project Layout

Repositories are cloned into `~/projects/<repo-name>`. Package restore runs automatically after cloning:

- `.sln` found → `dotnet restore`
- `package.json` found → `npm install`

## Ports

The **.NET API** and **Frontend** apps in the sidebar are proxied port forwards. Start your services on the configured ports and they'll be accessible from the links in the workspace dashboard.

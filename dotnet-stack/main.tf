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

data "coder_parameter" "repo" {
  name         = "Repository"
  display_name = "Repository"
  description  = "Git repository to clone into the workspace"
  type         = "string"
  mutable      = false

  option {
    name  = "OrOut API"
    value = "git@github.com:yourorg/orout-api.git"
  }
  option {
    name  = "OrOut Frontend"
    value = "git@github.com:yourorg/orout-frontend.git"
  }
  option {
    name  = "DCWD Site"
    value = "git@github.com:yourorg/dcwd-web.git"
  }
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

# ── Persistent home volume ────────────────────────────────────────────────────

resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"
  lifecycle {
    ignore_changes = all
  }
}

# ── Agent ─────────────────────────────────────────────────────────────────────

resource "coder_agent" "main" {
  os   = "linux"
  arch = data.coder_provisioner.me.arch

  env = {
    GIT_AUTHOR_NAME     = data.coder_workspace_owner.me.full_name
    GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME  = data.coder_workspace_owner.me.full_name
    GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
  }

  startup_script = <<-EOF
    set -e

    # Install Claude Code if not already present
    if ! command -v claude &> /dev/null; then
      npm install -g @anthropic-ai/claude-code
    fi

    # Clone repo if not already present (persists across restarts via volume)
    REPO_DIR=~/project
    if [ ! -d "$REPO_DIR/.git" ]; then
      git clone ${data.coder_parameter.repo.value} "$REPO_DIR"
    fi

    # .NET restore
    if [ -f "$REPO_DIR"/*.sln ]; then
      dotnet restore "$REPO_DIR"
    fi

    # npm install if frontend project
    if [ -f "$REPO_DIR/package.json" ]; then
      cd "$REPO_DIR" && npm install
    fi
  EOF
}

# ── VS Code browser (code-server) ─────────────────────────────────────────────

resource "coder_app" "code_server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "VS Code"
  url          = "http://localhost:13337/?folder=/home/coder/project"
  icon         = "/icon/code.svg"
  subdomain    = false

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 5
    threshold = 15
  }
}

# ── .NET API port forward ──────────────────────────────────────────────────────

resource "coder_app" "api" {
  agent_id     = coder_agent.main.id
  slug         = "api"
  display_name = ".NET API"
  url          = "http://localhost:${data.coder_parameter.dotnet_port.value}"
  icon         = "/icon/dotnet.svg"
  subdomain    = false
  share        = "owner"
}

# ── Frontend dev server port forward ──────────────────────────────────────────

resource "coder_app" "frontend" {
  agent_id     = coder_agent.main.id
  slug         = "frontend"
  display_name = "Frontend"
  url          = "http://localhost:${data.coder_parameter.frontend_port.value}"
  icon         = "/icon/nodejs.svg"
  subdomain    = false
  share        = "owner"
}

# ── Docker image & container ───────────────────────────────────────────────────

resource "docker_image" "workspace" {
  name = "coder-dotnet-stack-${data.coder_workspace.me.id}"
  build {
    context = path.module
  }
  # Rebuild image when Dockerfile changes
  triggers = {
    dockerfile = filesha256("${path.module}/Dockerfile")
  }
  keep_locally = true
}

resource "docker_container" "workspace" {
  # Only run the container when the workspace is started
  count = data.coder_workspace.me.start_count

  name  = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"
  image = docker_image.workspace.image_id

  # Coder agent token injected automatically
  env = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]

  command = [
    "sh", "-c",
    coder_agent.main.init_script
  ]

  volumes {
    volume_name    = docker_volume.home_volume.name
    container_path = "/home/coder"
    read_only      = false
  }

  # Allows dotnet, npm, git to work correctly
  capabilities {
    add = ["SYS_PTRACE"]
  }

  # Keep container running
  must_run = true
}
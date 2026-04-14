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

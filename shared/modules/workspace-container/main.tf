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
    context    = var.image_context
    dockerfile = var.dockerfile
    build_args = var.build_args
  }
  triggers = {
    dockerfile = filesha256("${var.image_context}/${var.dockerfile}")
    build_args = sha256(jsonencode(var.build_args))
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

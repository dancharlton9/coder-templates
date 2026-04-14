terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
  }
}

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

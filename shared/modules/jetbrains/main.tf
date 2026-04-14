terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
  }
}

resource "coder_app" "jetbrains" {
  for_each = var.ides

  agent_id     = var.agent_id
  slug         = each.key
  display_name = each.value.display_name
  icon         = each.value.icon
  url          = "jetbrains-gateway://connect#type=coder&workspace=${var.workspace_name}&owner=${var.owner_name}&folder=${var.folder}&ide_product_code=${each.value.ide_product_code}&ide_build_number=${each.value.ide_build_number}"
  external     = true
}

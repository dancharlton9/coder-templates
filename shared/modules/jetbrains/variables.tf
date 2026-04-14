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
      ide_build_number = "253.31033.136"
    }
    webstorm = {
      display_name     = "WebStorm"
      icon             = "/icon/webstorm.svg"
      ide_product_code = "WS"
      ide_build_number = "253.31033.133"
    }
    datagrip = {
      display_name     = "DataGrip"
      icon             = "/icon/datagrip.svg"
      ide_product_code = "DB"
      ide_build_number = "253.29346.270"
    }
  }
}

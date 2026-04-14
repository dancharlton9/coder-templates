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

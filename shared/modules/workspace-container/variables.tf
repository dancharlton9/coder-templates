variable "workspace_id" {
  type = string
}

variable "workspace_name" {
  type = string
}

variable "workspace_start_count" {
  type = number
}

variable "owner_name" {
  type = string
}

variable "owner_full_name" {
  type = string
}

variable "owner_email" {
  type = string
}

variable "arch" {
  type = string
}

variable "image_context" {
  type        = string
  description = "Path to the directory containing the Dockerfile"
}

variable "dockerfile" {
  type        = string
  description = "Path to Dockerfile relative to image_context"
  default     = "Dockerfile"
}

variable "startup_script" {
  type        = string
  description = "The full startup script for the agent"
}

variable "extra_env" {
  type        = map(string)
  description = "Additional environment variables for the agent"
  default     = {}
}

variable "docker_socket" {
  type        = bool
  description = "Whether to mount the Docker socket into the workspace"
  default     = true
}

variable "build_args" {
  type        = map(string)
  description = "Docker build arguments to pass to the image build"
  default     = {}
}

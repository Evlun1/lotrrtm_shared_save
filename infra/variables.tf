variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "eu-west-3"
}

variable "project_name" {
  description = "Base name for resources"
  type        = string
  default     = "lotrrtm-shared-save"
}

variable "ssm_parameter_name" {
  description = "Name for the SSM Parameter storing the lock status"
  type        = string
  default     = "lotrrtm-shared-save-lock_state"
}

variable "ssm_filename_parameter_name" {
  description = "Name for the SSM Parameter storing the last uploaded filename"
  type        = string
  default     = "lotrrtm-shared-save-last_filename"
}

variable "ssm_password_parameter_name" {
  description = "Name for the SSM Parameter storing the last uploaded filename"
  type        = string
  default     = "lotrrtm-shared-save-password"
}

variable "ssm_initial_value" {
  description = "Initial value for the SSM Parameters"
  type        = string
  default     = "init"
}

variable "ssm_password_value" {
  description = "Initialize your own password for the app through env variables"
  type = string
}

variable "project" {
  description = "Short project name, used in resource naming. Lowercase, no hyphens (storage accounts are fussy)."
  type        = string
  default     = "gbpipeline"
}

variable "environment" {
  description = "Environment name, used in resource naming and tags."
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "centralus"
}

variable "address_space" {
  description = "VNet CIDR."
  type        = string
  default     = "10.42.0.0/16"
}

variable "owner" {
  description = "Owner tag. The thing you enforced with Azure Policy at Thesis after cleaning up the sprawl."
  type        = string
  default     = "gary.byrd"
}

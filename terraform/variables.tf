# Only declaring the variables

variable "environment" {
  type    = string
  default = "dev"
}

variable "location" {
  type    = string
  default = "eastus" 
}

variable "subscription_id" {
  type = string
}
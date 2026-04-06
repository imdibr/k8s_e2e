variable "vpc_id" {
  description = "The ID of the VPC where Jenkins will be deployed"
  type        = string
}

variable "public_subnet_id" {
  description = "The ID of the public subnet for the Jenkins instance"
  type        = string
}
variable "admin_ip" {
  type        = string
  description = "The public IP address of the admin"
}
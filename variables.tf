variable "controller_aws_account_number" {
  description = "AWS account number where the controller runs"
  default = "425355469185"
}

variable "controller_dev_aws_account_number" {
  description = "AWS account number where the dev controllers run"
  default = "705482507833"
}

variable "zones" {
  description = "All the resource will be created with this prefix Example : qa-saahil-terraform"
  default = 2
}

variable "prefix" {
  description = "All the resource will be created with this prefix Example : qa-saahil-terraform"
}

variable "key_name" {
  description = "SSH Keypair name"
}

variable "edge_vpc_cidr" {
  description = "Edge VPC CIDR for deploying valtix in edge mode"
  default = "10.0.0.0/16"
}

variable "dev_web_vpc_cidr" {
  description = "Dev web VPC CIDR (used in tgw mode)"
  default = "10.1.0.0/16"
}

variable "prod_web_vpc_cidr" {
  description = "Prod web VPC CIDE (used in tgw mode)"
  default = "10.2.0.0/16"
}

variable "db_vpc_cidr" {
  description = "DB CIDR for the VPC"
  default = "10.3.0.0/16"
}

variable "subnet_bits" {
  description = "Number of additional bits (on top of the vpc cidr mask) to use in the subnets inside VPC (final subnet would be the mask of vpc cidr + the value provided for this variable)"
  default = 8
}


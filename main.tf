provider "aws" {
  region = "us-east-1"
}

# Declare the data source
data "aws_availability_zones" "available" {}

data "aws_ami" "qa-mgmt-jumpbox" {
  most_recent = true
  owners      = ["902505820678"]
  name_regex  = "^valtix-sandbox-server"
}

data "aws_ami" "qa-backend" {
  most_recent = true
  owners      = ["902505820678"]
  name_regex  = "^valtix-sandbox-server"
}

resource "aws_key_pair" "ssh-key" {
  key_name = "sandbox"
  public_key = file(format("${dirname(path.cwd)}/keys/%s.pub", var.key_name))
}

resource "aws_s3_bucket" "techsupport" {
  bucket = format("valtix-%s-techsupport", replace(var.prefix, "_", "-"))
  acl    = "private"
  tags = {
    Name   = "valtix-${var.prefix}-techsupport"
    prefix = var.prefix
  }
}

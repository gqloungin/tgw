resource "aws_vpc" "dev_web_vpc" {
  cidr_block = var.dev_web_vpc_cidr

  tags = {
    Name   = "dev_web_vpc"
    prefix = var.prefix
  }
}

resource "aws_default_route_table" "dev_web_vpc_default_rtable" {
  default_route_table_id = aws_vpc.dev_web_vpc.default_route_table_id

  tags = {
    Name   = "dev_web_vpc_default"
    prefix = var.prefix
  }
}

# create internet gw and attach it to the vpc
resource "aws_internet_gateway" "dev_web_vpc_gw" {
  vpc_id = aws_vpc.dev_web_vpc.id

  tags = {
    Name   = "dev_web_vpc_igw"
    prefix = var.prefix
  }
}

# Two subnets per AZ, called mgmt, backend.
# subnets are created in each of the zones
# 10.0.0.0 backend, 10.0.1.0 mgmt and it continues in other zones in increments of 3
# (10.0.2.0 and its peers are not used or reserved for future expansion)

resource "aws_subnet" "dev_web_vpc_backend" {
  vpc_id            = aws_vpc.dev_web_vpc.id
  count             = var.zones
  cidr_block        = cidrsubnet(var.dev_web_vpc_cidr, var.subnet_bits, (count.index * 3))
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name   = "dev_web_vpc_z${count.index + 1}_backend"
    prefix = var.prefix
  }
}

resource "aws_subnet" "dev_web_vpc_mgmt" {
  vpc_id            = aws_vpc.dev_web_vpc.id
  count             = var.zones
  cidr_block        = cidrsubnet(var.dev_web_vpc_cidr, var.subnet_bits, (count.index * 3) + 1)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name   = "dev_web_vpc_z${count.index + 1}_mgmt"
    prefix = var.prefix
  }
}

resource "aws_route_table" "dev_web_vpc_backend" {
  vpc_id = aws_vpc.dev_web_vpc.id
  count  = var.zones

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.dev_web_vpc_gw.id
  }

  tags = {
    Name   = "dev_web_vpc_z${count.index + 1}_backend"
    prefix = var.prefix
  }
}

# associate backend route table with backend subnet
resource "aws_route_table_association" "dev_web_vpc_backend" {
  count          = var.zones
  subnet_id      = aws_subnet.dev_web_vpc_backend[count.index].id
  route_table_id = aws_route_table.dev_web_vpc_backend[count.index].id
}

resource "aws_route_table" "dev_web_vpc_mgmt" {
  vpc_id = aws_vpc.dev_web_vpc.id
  count  = var.zones

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.dev_web_vpc_gw.id
  }

  tags = {
    Name   = "dev_web_vpc_z${count.index + 1}_mgmt"
    prefix = var.prefix
  }
}

# associate mgmt route table with mgmt subnet
resource "aws_route_table_association" "dev_web_vpc_mgmt" {
  count          = var.zones
  subnet_id      = aws_subnet.dev_web_vpc_mgmt[count.index].id
  route_table_id = aws_route_table.dev_web_vpc_mgmt[count.index].id
}


# jumpbox security group to allow ssh to jumpbox and all egress traffic
resource "aws_security_group" "dev_web_vpc_jumpbox" {
  name   = "jumpbox"
  vpc_id = aws_vpc.dev_web_vpc.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name   = "jumpbox"
    prefix = var.prefix
  }
}

# backend sg is used by the instances running the customer apps.
# by default this is setup to open ports 80 and 443. customer must add
# ports when the new apps are launched on other ports. since the
# customer apps are expected to be in a private subnet, there is no
# reachability to the subnet from outside the vpc. Outbound rules are
# opened wide for intra-vpc communications. Customer can change/restrict
# as required.
resource "aws_security_group" "dev_web_vpc_backend" {
  name   = "dev_web_vpc_backend"
  vpc_id = aws_vpc.dev_web_vpc.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name   = "dev_web_vpc_backend"
    prefix = var.prefix
  }
}

# create 1 backend host in each zone
resource "aws_instance" "dev_web_vpc_backend" {
  ami                         = data.aws_ami.qa-backend.id
  associate_public_ip_address = true
  count                       = var.zones
  key_name                    = aws_key_pair.ssh-key.key_name
  instance_type               = "t3a.medium"
  vpc_security_group_ids      = [aws_security_group.dev_web_vpc_backend.id]
  subnet_id                   = aws_subnet.dev_web_vpc_backend[count.index].id
  availability_zone           = data.aws_availability_zones.available.names[count.index]

  root_block_device {
    delete_on_termination = true
  }

  tags = {
    Name   = "dev_web_vpc_backend-${count.index + 1}"
    prefix = var.prefix
    role   = "dev"
  }
  volume_tags = {
    Name   = "dev_web_vpc_backend-${count.index + 1}"
    prefix = var.prefix
  }
  user_data = <<EOF
#!/bin/bash
docker pull ubuntu:16.04
docker pull mysql
EOF

}

# one instance for mgmt/jumpbox
resource "aws_instance" "dev_web_vpc_jumpbox" {
  ami                         = data.aws_ami.qa-mgmt-jumpbox.id
  associate_public_ip_address = true
  key_name                    = aws_key_pair.ssh-key.key_name
  instance_type               = "t3a.micro"
  vpc_security_group_ids      = [aws_security_group.dev_web_vpc_jumpbox.id]
  subnet_id                   = aws_subnet.dev_web_vpc_mgmt[0].id

  provisioner "file" {
    source      = format("${dirname(path.cwd)}/keys/%s", var.key_name)
    destination = "/home/centos/.ssh/id_rsa"
    connection {
      type        = "ssh"
      user        = "centos"
      private_key = file(format("${dirname(path.cwd)}/keys/%s", var.key_name))
      host        = aws_instance.dev_web_vpc_jumpbox.public_ip
    }
  }

  root_block_device {
    delete_on_termination = true
  }

  tags = {
    Name   = "dev_web_vpc_jumpbox"
    prefix = var.prefix
  }
  volume_tags = {
    Name   = "dev_web_vpc_jumpbox"
    prefix = var.prefix
  }
}

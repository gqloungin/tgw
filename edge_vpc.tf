resource "aws_vpc" "edge_vpc" {
  cidr_block = var.edge_vpc_cidr

  tags = {
    Name   = "edge_vpc"
    prefix = var.prefix
  }
}

resource "aws_default_route_table" "edge_vpc_default_rtable" {
  default_route_table_id = aws_vpc.edge_vpc.default_route_table_id

  tags = {
    Name   = "edge_vpc_default"
    prefix = var.prefix
  }
}

# create internet gw and attach it to the vpc
resource "aws_internet_gateway" "edge_vpc_gw" {
  vpc_id = aws_vpc.edge_vpc.id

  tags = {
    Name   = "edge_vpc_igw"
    prefix = var.prefix
  }
}

# Three Subnets backend/datapath/mgmt
# datapath would host the NLB, has default route to the igw
# used by valtix firewall to receive traffic from the internet.
# mgmt subnet has default route to the igw and allows outbound
# traffic to communicate with the controller.
# backend subnet hosts all the customer apps.
# subnets are created in each of the zones
# 10.0.0.0 backend, 10.0.1.0 datapath, 10.0.2.0 mgmt
# and it continues in other zones in increments of 5
# (10.0.3.0 and 10.0.4.0 and its peers are not used)

resource "aws_subnet" "edge_vpc_backend" {
  vpc_id            = aws_vpc.edge_vpc.id
  count             = var.zones
  cidr_block        = cidrsubnet(var.edge_vpc_cidr, var.subnet_bits, (count.index * 5))
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name   = "edge_vpc_z${count.index + 1}_backend"
    prefix = var.prefix
  }
}

resource "aws_subnet" "edge_vpc_datapath" {
  vpc_id            = aws_vpc.edge_vpc.id
  count             = var.zones
  cidr_block        = cidrsubnet(var.edge_vpc_cidr, var.subnet_bits, (count.index * 5) + 1)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name   = "edge_vpc_z${count.index + 1}_datapath"
    prefix = var.prefix
  }
}

resource "aws_subnet" "edge_vpc_mgmt" {
  vpc_id            = aws_vpc.edge_vpc.id
  count             = var.zones
  cidr_block        = cidrsubnet(var.edge_vpc_cidr, var.subnet_bits, (count.index * 5) + 2)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name   = "edge_vpc_z${count.index + 1}_mgmt"
    prefix = var.prefix
  }
}

# dont use default route table for any route changes. create subnet
# specific route table for any route info

# mgmt route table associated with mgmt subnet and has a default route
# to point to the igw
resource "aws_route_table" "edge_vpc_mgmt" {
  vpc_id = aws_vpc.edge_vpc.id
  count  = var.zones

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.edge_vpc_gw.id
  }

  tags = {
    Name   = "edge_vpc_z${count.index + 1}_mgmt"
    prefix = var.prefix
  }
}

# datapath route table associated with datapath subnet and has a default
# route to point to the igw
resource "aws_route_table" "edge_vpc_datapath" {
  vpc_id = aws_vpc.edge_vpc.id
  count  = var.zones

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.edge_vpc_gw.id
  }

  tags = {
    Name   = "edge_vpc_z${count.index + 1}_datapath"
    prefix = var.prefix
  }
}

resource "aws_route_table" "edge_vpc_backend" {
  vpc_id = aws_vpc.edge_vpc.id
  count  = var.zones

  tags = {
    Name   = "edge_vpc_z${count.index + 1}_backend"
    prefix = var.prefix
  }
}

# associate mgmt route table with mgmt subnet
resource "aws_route_table_association" "edge_vpc_mgmt" {
  count          = var.zones
  subnet_id      = aws_subnet.edge_vpc_mgmt[count.index].id
  route_table_id = aws_route_table.edge_vpc_mgmt[count.index].id
}

# associate datapath route table with datapath subnet
resource "aws_route_table_association" "edge_vpc_datapath" {
  count          = var.zones
  subnet_id      = aws_subnet.edge_vpc_datapath[count.index].id
  route_table_id = aws_route_table.edge_vpc_datapath[count.index].id
}

# associate backend route table with backend subnet
resource "aws_route_table_association" "edge_vpc_backend" {
  count          = var.zones
  subnet_id      = aws_subnet.edge_vpc_backend[count.index].id
  route_table_id = aws_route_table.edge_vpc_backend[count.index].id
}

# security groups for datapath, backend, mgmt and customer_apps

# datapath is connected to the NLB and also to the incoming interface on
# the valtix fw. inbound rules setup to open 80 and 443.
# health check port on 65534 for the NLB to do health checks on firewall
# no outbound rules. so traffic cannot be initiated by firewall to go
# out on the datapath interface.
resource "aws_security_group" "edge_vpc_datapath" {
  name   = "edge_vpc_datapath"
  vpc_id = aws_vpc.edge_vpc.id

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
    from_port   = 65534
    to_port     = 65534
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
    Name   = "edge_vpc_datapath"
    prefix = var.prefix
  }
}

# mgmt sg is applied to the mgmt interface on the valtix fw. traffic is
# not initiated towards this interface. so there are not inbound rules.
# fw communicates with the controller on this interface/sg. so outbound
# rules must be enabled to allow traffic to reach controller. this is
# setup to open ports 8091-8092. since the controller runs on ALB on
# aws, we can't open to a specific destination ip address.
# So the destination ip is setup to 0.0.0.0

resource "aws_security_group" "edge_vpc_mgmt" {
  name   = "edge_vpc_mgmt"
  vpc_id = aws_vpc.edge_vpc.id
  egress {
    from_port   = 8091
    to_port     = 8092
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name   = "edge_vpc_mgmt"
    prefix = var.prefix
  }
}

# jumpbox security group to allow ssh to jumpbox and all egress traffic
resource "aws_security_group" "edge_vpc_jumpbox" {
  name   = "edge_vpc_jumpbox"
  vpc_id = aws_vpc.edge_vpc.id
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
    Name   = "edge_vpc_jumpbox"
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
resource "aws_security_group" "edge_vpc_backend" {
  name   = "edge_vpc_backend"
  vpc_id = aws_vpc.edge_vpc.id
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
    Name   = "edge_vpc_backend"
    prefix = var.prefix
  }
}

# create 1 backend host in each zone
resource "aws_instance" "edge_vpc_backend" {
  ami                         = data.aws_ami.qa-backend.id
  associate_public_ip_address = true
  count                       = var.zones
  key_name                    = aws_key_pair.ssh-key.key_name
  instance_type               = "t3a.micro"
  vpc_security_group_ids      = [aws_security_group.edge_vpc_backend.id]
  subnet_id                   = aws_subnet.edge_vpc_backend[count.index].id
  availability_zone           = data.aws_availability_zones.available.names[count.index]

  root_block_device {
    delete_on_termination = true
  }

  tags = {
    Name   = "edge_vpc_backend-${count.index + 1}"
    prefix = var.prefix

  }
  volume_tags = {
    Name   = "edge_vpc_backend-${count.index + 1}"
    prefix = var.prefix
  }
}

# one instance for mgmt/jumpbox
resource "aws_instance" "edge_vpc_jumpbox" {
  ami                         = data.aws_ami.qa-mgmt-jumpbox.id
  associate_public_ip_address = true
  key_name                    = aws_key_pair.ssh-key.key_name
  instance_type               = "t3a.micro"
  vpc_security_group_ids      = [aws_security_group.edge_vpc_jumpbox.id]
  subnet_id                   = aws_subnet.edge_vpc_mgmt[0].id

  root_block_device {
    delete_on_termination = true
  }

  tags = {
    Name   = "edge_vpc_jumpbox"
    prefix = var.prefix
  }
  volume_tags = {
    Name   = "edge_vpc_jumpbox"
    prefix = var.prefix
  }
}


resource "aws_lb" "edge_vpc_backend_lb" {
  name               = "edge-vpc-backend-lb"
  load_balancer_type = "network"
  internal           = true
  subnet_mapping {
    subnet_id = aws_subnet.edge_vpc_mgmt[0].id
  }
  subnet_mapping {
    subnet_id = aws_subnet.edge_vpc_mgmt[1].id
  }
  tags = {
    Name = "backend-lb"
    Application = "backend-lb"
  }
}

resource "aws_lb_listener" "edge_vpc_backend_lb_listener_443" {
  load_balancer_arn = aws_lb.edge_vpc_backend_lb.arn
  port              = "443"
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.edge_vpc_backend_tg_443.arn
  }
}

resource "aws_lb_listener" "edge_vpc_backend_lb_listener_80" {
  load_balancer_arn = aws_lb.edge_vpc_backend_lb.arn
  port              = "80"
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.edge_vpc_backend_tg_80.arn
  }
}

resource "aws_lb_target_group" "edge_vpc_backend_tg_443" {
  name     = "edge-vpc-backend-tg-443"
  port     = "443"
  protocol = "TCP"
  vpc_id   = aws_vpc.edge_vpc.id
}

resource "aws_lb_target_group" "edge_vpc_backend_tg_80" {
  name     = "edge-vpc-backend-tg-80"
  port     = "80"
  protocol = "TCP"
  vpc_id   = aws_vpc.edge_vpc.id
}

resource "aws_lb_target_group_attachment" "edge_vpc_backend_443" {
  count            = var.zones
  target_group_arn = aws_lb_target_group.edge_vpc_backend_tg_443.arn
  target_id        = aws_instance.edge_vpc_backend[count.index].id
  port             = 443
}

resource "aws_lb_target_group_attachment" "edge_vpc_backend_80" {
  count            = var.zones
  target_group_arn = aws_lb_target_group.edge_vpc_backend_tg_80.arn
  target_id        = aws_instance.edge_vpc_backend[count.index].id
  port             = 80
}

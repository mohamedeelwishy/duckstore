data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd*/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# =============================================================================
# Security Group
# =============================================================================

resource "aws_security_group" "node" {
  name        = "${local.name}-node-sg"
  description = "Ingress rules for the single-node K3s cluster"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name}-node-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.node.id
  description       = "HTTP - Traefik ingress"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.node.id
  description       = "HTTPS - Traefik ingress"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = toset(var.ssh_allowed_cidrs)

  security_group_id = aws_security_group.node.id
  description       = "SSH from ${each.value}"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "kube_api" {
  for_each = toset(var.k8s_api_allowed_cidrs)

  security_group_id = aws_security_group.node.id
  description       = "Kubernetes API from ${each.value}"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 6443
  to_port           = 6443
}

resource "aws_vpc_security_group_ingress_rule" "nodeport" {
  count = var.enable_nodeport_range ? 1 : 0

  security_group_id = aws_security_group.node.id
  description       = "Kubernetes NodePort range"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 30000
  to_port           = 32767
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.node.id
  description       = "Allow all outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# =============================================================================
# IAM — Instance Profile
# =============================================================================

resource "aws_iam_role" "node" {
  name = "${local.name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "node" {
  name = "${local.name}-node-profile"
  role = aws_iam_role.node.name
}

# =============================================================================
# Elastic IP
# =============================================================================

resource "aws_eip" "node" {
  domain = "vpc"

  tags = {
    Name = "${local.name}-eip"
  }
}

# =============================================================================
# EC2 Instance
# =============================================================================

resource "aws_instance" "node" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public.id

  vpc_security_group_ids = [aws_security_group.node.id]
  iam_instance_profile   = aws_iam_instance_profile.node.name

  key_name = var.key_pair_name != "" ? var.key_pair_name : null

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "${local.name}-root"
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  user_data = templatefile("${path.module}/user_data.sh", {
    elastic_ip             = aws_eip.node.public_ip
    k3s_version            = var.k3s_version
    domain_name            = var.domain_name
    disable_metrics_server = var.disable_metrics_server
  })

  user_data_replace_on_change = false

  # Protect persistent local-path storage (SQLite database) from accidental destruction
  # caused by user_data script changes or upstream Ubuntu AMI upgrades.
  lifecycle {
    ignore_changes = [user_data, ami]
  }

  tags = {
    Name = "${local.name}-k3s-node"
    Role = "k3s-server"
  }
}

resource "aws_eip_association" "node" {
  instance_id   = aws_instance.node.id
  allocation_id = aws_eip.node.id
}

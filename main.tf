# ---------------------------------------------------------------------------
# Validaciones: la Local Zone debe estar disponible y habilitada (opt-in),
# y debe existir una subnet en ella.
# ---------------------------------------------------------------------------

data "aws_availability_zone" "bogota" {
  name                   = var.local_zone_name
  all_availability_zones = true

  lifecycle {
    postcondition {
      condition     = self.zone_type == "local-zone" && self.state == "available"
      error_message = "La zona ${var.local_zone_name} no es una Local Zone disponible."
    }
    postcondition {
      condition     = self.opt_in_status == "opted-in"
      error_message = "La Local Zone ${var.local_zone_name} no está habilitada. Actívala con: aws ec2 modify-availability-zone-group --region ${var.region} --group-name ${self.group_name} --opt-in-status opted-in"
    }
  }
}

data "aws_vpc" "default" {
  default = true
}

# Subnet existente en la Local Zone (falla si no hay ninguna o hay más de una).
data "aws_subnet" "bogota" {
  vpc_id            = data.aws_vpc.default.id
  availability_zone = data.aws_availability_zone.bogota.name
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# ---------------------------------------------------------------------------
# IAM: acceso por Session Manager, sin llaves SSH ni puerto 22 abierto.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${var.name}-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.name}-profile"
  role = aws_iam_role.instance.name
}

# ---------------------------------------------------------------------------
# Security group. Sin SSH.
#   Entrada: HTTP (nginx), ping (ICMP echo) e iperf3 (5201 TCP/UDP).
#   Salida:  HTTP/HTTPS (SSM y repos), ICMP e iperf3 (para pruebas como cliente).
# ---------------------------------------------------------------------------

resource "aws_security_group" "instance" {
  name        = "${var.name}-sg"
  description = "EC2 en la Local Zone de Bogota: ingress HTTP, egress HTTP/HTTPS"
  vpc_id      = data.aws_vpc.default.id

  tags = {
    Name = "${var.name}-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  for_each = toset(var.http_ingress_cidrs)

  security_group_id = aws_security_group.instance.id
  description       = "HTTP entrante a nginx"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "ping" {
  for_each = toset(var.icmp_ingress_cidrs)

  security_group_id = aws_security_group.instance.id
  description       = "Ping entrante (ICMP echo request)"
  cidr_ipv4         = each.value
  ip_protocol       = "icmp"
  from_port         = 8 # tipo ICMP: echo request
  to_port           = -1
}

# IP pública de quien ejecuta terraform; solo se consulta si no se definen
# CIDRs para iperf3.
data "http" "my_ip" {
  count = length(var.iperf3_ingress_cidrs) == 0 ? 1 : 0
  url   = "https://checkip.amazonaws.com"
}

locals {
  iperf3_cidrs = length(var.iperf3_ingress_cidrs) > 0 ? var.iperf3_ingress_cidrs : ["${chomp(data.http.my_ip[0].response_body)}/32"]

  iperf3_ingress = {
    for pair in setproduct(local.iperf3_cidrs, ["tcp", "udp"]) :
    "${pair[1]}-${pair[0]}" => { cidr = pair[0], protocol = pair[1] }
  }
}

resource "aws_vpc_security_group_ingress_rule" "iperf3" {
  for_each = local.iperf3_ingress

  security_group_id = aws_security_group.instance.id
  description       = "iperf3 entrante (${each.value.protocol})"
  cidr_ipv4         = each.value.cidr
  ip_protocol       = each.value.protocol
  from_port         = 5201
  to_port           = 5201
}

resource "aws_vpc_security_group_egress_rule" "icmp" {
  security_group_id = aws_security_group.instance.id
  description       = "ICMP saliente (ping y traceroute desde la instancia)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "icmp"
  from_port         = -1
  to_port           = -1
}

resource "aws_vpc_security_group_egress_rule" "iperf3" {
  for_each = toset(["tcp", "udp"])

  security_group_id = aws_security_group.instance.id
  description       = "iperf3 saliente (${each.value}), instancia como cliente"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = each.value
  from_port         = 5201
  to_port           = 5201
}

resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.instance.id
  description       = "HTTPS saliente (SSM, APIs de AWS, repos)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "http" {
  security_group_id = aws_security_group.instance.id
  description       = "HTTP saliente (repos de paquetes)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

# ---------------------------------------------------------------------------
# Instancia EC2
# ---------------------------------------------------------------------------

resource "aws_instance" "this" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnet.bogota.id
  vpc_security_group_ids = [aws_security_group.instance.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name

  # La subnet no asigna IP pública por defecto y su única salida es el
  # internet gateway, así que la instancia necesita IP pública para llegar
  # a SSM. La IP sale del network border group us-east-1-bog-1.
  associate_public_ip_address = true

  # Instala nginx y genera la página con los metadatos. Si el script cambia,
  # la instancia se reemplaza para que vuelva a ejecutarse.
  user_data                   = file("${path.module}/user-data.sh")
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = var.name
  }

  volume_tags = merge(var.tags, {
    Name = "${var.name}-root"
  })

  lifecycle {
    # Evita reemplazar la instancia cada vez que AWS publica una AMI nueva.
    ignore_changes = [ami]
  }
}

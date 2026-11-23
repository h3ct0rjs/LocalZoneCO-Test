output "local_zone" {
  description = "Estado de la Local Zone."
  value = {
    name          = data.aws_availability_zone.bogota.name
    zone_id       = data.aws_availability_zone.bogota.zone_id
    state         = data.aws_availability_zone.bogota.state
    opt_in_status = data.aws_availability_zone.bogota.opt_in_status
    parent_zone   = data.aws_availability_zone.bogota.parent_zone_name
  }
}

output "subnet" {
  description = "Subnet usada en la Local Zone."
  value = {
    id   = data.aws_subnet.bogota.id
    cidr = data.aws_subnet.bogota.cidr_block
  }
}

output "instance_id" {
  value = aws_instance.this.id
}

output "public_ip" {
  value = aws_instance.this.public_ip
}

output "private_ip" {
  value = aws_instance.this.private_ip
}

output "web_url" {
  description = "Página de nginx con los metadatos (tarda 1-2 minutos tras el arranque)."
  value       = "http://${aws_instance.this.public_ip}"
}

output "iperf3_allowed_cidrs" {
  description = "CIDRs con acceso al servidor iperf3."
  value       = local.iperf3_cidrs
}

output "network_test_commands" {
  description = "Pruebas de red desde tu máquina hacia la instancia."
  value = {
    ping            = "ping -c 20 ${aws_instance.this.public_ip}"
    iperf3_upload   = "iperf3 -c ${aws_instance.this.public_ip} -t 10"
    iperf3_download = "iperf3 -c ${aws_instance.this.public_ip} -t 10 -R"
    iperf3_udp      = "iperf3 -c ${aws_instance.this.public_ip} -u -b 100M -t 10"
  }
}

output "ssm_connect_command" {
  description = "Comando para conectarse por Session Manager."
  value       = "aws ssm start-session --region ${var.region} --target ${aws_instance.this.id}"
}

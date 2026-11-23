variable "region" {
  description = "Región padre de la Local Zone."
  type        = string
  default     = "us-east-1"
}

variable "local_zone_name" {
  description = "Nombre de la Local Zone de Bogotá."
  type        = string
  default     = "us-east-1-bog-1a"
}

variable "name" {
  description = "Prefijo para los nombres de los recursos."
  type        = string
  default     = "bog-localzone-test"
}

variable "instance_type" {
  description = "Tipo de instancia. Bogotá solo ofrece las familias c7i, m7i y r7i (no hay t3/t4g)."
  type        = string
  default     = "c7i.large"

  validation {
    condition     = can(regex("^(c7i|m7i|r7i)\\.", var.instance_type))
    error_message = "La Local Zone de Bogotá solo ofrece instancias c7i, m7i y r7i."
  }
}

variable "root_volume_size_gb" {
  description = "Tamaño del volumen raíz en GiB."
  type        = number
  default     = 30
}

variable "http_ingress_cidrs" {
  description = "CIDRs que pueden abrir la página de nginx (puerto 80). Restringe a tu IP con [\"x.x.x.x/32\"]; lista vacía cierra el acceso."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "icmp_ingress_cidrs" {
  description = "CIDRs que pueden hacer ping (ICMP echo request) a la instancia. Lista vacía lo desactiva."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "iperf3_ingress_cidrs" {
  description = "CIDRs que pueden usar el servidor iperf3 (puerto 5201 TCP/UDP). Si se deja vacío se usa la IP pública de quien ejecuta terraform."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags aplicados a todos los recursos."
  type        = map(string)
  default = {
    Project     = "testLocalZoneCO"
    Environment = "test"
    ManagedBy   = "terraform"
  }
}

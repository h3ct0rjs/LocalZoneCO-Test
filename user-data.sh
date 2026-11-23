#!/bin/bash
# Instala nginx con una página de metadatos (IMDSv2) y deja iperf3 corriendo
# como servidor en el puerto 5201 para pruebas de red.
set -euxo pipefail

dnf install -y nginx iperf3

cat > /etc/systemd/system/iperf3-server.service <<'UNIT'
[Unit]
Description=iperf3 server
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/iperf3 --server --port 5201
Restart=always
RestartSec=2
DynamicUser=yes

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now iperf3-server

IMDS="http://169.254.169.254/latest"
TOKEN=$(curl -sS -X PUT "$IMDS/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300")

# Devuelve el valor del metadato o "N/A" si no existe.
md() {
  curl -sS -f -H "X-aws-ec2-metadata-token: $TOKEN" "$IMDS/meta-data/$1" 2>/dev/null || echo "N/A"
}

INSTANCE_ID=$(md instance-id)
INSTANCE_TYPE=$(md instance-type)
AMI_ID=$(md ami-id)
AZ=$(md placement/availability-zone)
AZ_ID=$(md placement/availability-zone-id)
REGION=$(md placement/region)
PRIVATE_IP=$(md local-ipv4)
PUBLIC_IP=$(md public-ipv4)
HOSTNAME_INT=$(md local-hostname)
MAC=$(md mac)
GENERATED_AT=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

cat > /usr/share/nginx/html/index.html <<EOF
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>AWS Local Zone Colombia</title>
  <style>
    body { font-family: system-ui, -apple-system, sans-serif; background: #232f3e; color: #fff; margin: 0; padding: 2rem 1rem; }
    main { max-width: 640px; margin: 0 auto; }
    h1 { color: #ff9900; margin-bottom: 0.25rem; }
    p { color: #d5dbdb; margin-top: 0; }
    table { width: 100%; border-collapse: collapse; margin-top: 1.5rem; }
    th, td { text-align: left; padding: 0.6rem 0.75rem; border-bottom: 1px solid #37475a; }
    th { color: #ff9900; font-weight: 600; width: 40%; }
    td { font-family: ui-monospace, Menlo, monospace; word-break: break-all; }
    footer { margin-top: 1.5rem; font-size: 0.85rem; color: #879596; }
  </style>
</head>
<body>
  <main>
    <h1>AWS Local Zone Colombia</h1>
    <p>Bogot&aacute; &mdash; servido por nginx desde una instancia EC2</p>
    <table>
      <tr><th>Instance ID</th><td>$INSTANCE_ID</td></tr>
      <tr><th>Tipo de instancia</th><td>$INSTANCE_TYPE</td></tr>
      <tr><th>AMI</th><td>$AMI_ID</td></tr>
      <tr><th>Zona</th><td>$AZ</td></tr>
      <tr><th>Zone ID</th><td>$AZ_ID</td></tr>
      <tr><th>Regi&oacute;n padre</th><td>$REGION</td></tr>
      <tr><th>IP privada</th><td>$PRIVATE_IP</td></tr>
      <tr><th>IP p&uacute;blica</th><td>$PUBLIC_IP</td></tr>
      <tr><th>Hostname</th><td>$HOSTNAME_INT</td></tr>
      <tr><th>MAC</th><td>$MAC</td></tr>
    </table>
    <footer>Generado al arrancar: $GENERATED_AT</footer>
  </main>
</body>
</html>
EOF

systemctl enable --now nginx

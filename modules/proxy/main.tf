resource "google_service_account" "disbursement_proxy_v2" {
  account_id   = "disbursement-proxy-v2-${var.client_name}"
  display_name = "Proxy ${var.client_name} Service Account"
}

resource "google_compute_firewall" "disbursement_proxy_v2" {
  name    = "disbursement-proxy-v2-${var.client_name}-firewall"
  network = "default"

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"

    ports = [
      "80",
      "443",
    ]
  }

  source_tags = []
  target_tags = [
    "disbursement-proxy-v2-${var.client_name}",
  ]
}

data "google_dns_managed_zone" "dns_zone" {
  name = var.dns_zone_name
}

resource "google_compute_address" "disbursement_proxy_v2" {
  name         = "disbursement-proxy-v2-${var.client_name}-static-ip"
  address_type = "EXTERNAL"
}

resource "google_dns_record_set" "disbursement_proxy_v2" {
  managed_zone = var.dns_zone_name
  name    = "${replace(google_compute_address.disbursement_proxy_v2.address, ".", "-")}.${data.google_dns_managed_zone.dns_zone.dns_name}"
  type    = "A"
  rrdatas = [google_compute_address.disbursement_proxy_v2.address]
  ttl     = 300
}

resource "google_compute_https_health_check" "disbursement_proxy_v2" {
  name                = "disbursement-proxy-v2-${var.client_name}-https-healthcheck"
  check_interval_sec  = 5
  timeout_sec         = 2
  healthy_threshold   = 2
  unhealthy_threshold = 10

  host         = google_dns_record_set.disbursement_proxy_v2.name
  request_path = "/healthz"
}

resource "google_monitoring_uptime_check_config" "disbursement_proxy_v2" {
  display_name = "disbursement-proxy-v2-${var.client_name}-uptime-check"
  timeout      = "60s"
  period       = "60s"

  http_check {
    use_ssl = true
    path    = "/healthz"
  }

  monitored_resource {
    type = "uptime_url"

    labels = {
      project_id = var.project_id
      host       = google_dns_record_set.disbursement_proxy_v2.name
    }
  }
}

resource "google_monitoring_alert_policy" "disbursement_proxy_v2" {
  display_name = "Proxy uptime ${google_dns_record_set.disbursement_proxy_v2.name}"
  combiner     = "OR"

  conditions {
    display_name = "uptime check"

    condition_threshold {
      filter     = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" resource.type=\"uptime_url\""
      duration   = "120s"
      comparison = "COMPARISON_GT"

      trigger {
        count = 1
      }

      aggregations {
        alignment_period     = "60s"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
      }
    }
  }
}

resource "google_compute_instance_group_manager" "disbursement_proxy_v2" {
  provider           = google-beta
  name               = "disbursement-proxy-v2-manager-${var.client_name}"
  base_instance_name = "disbursement-proxy-v2-manager-${var.client_name}"
  zone               = var.zone
  target_size        = "1"

  version {
    name              = "proxy-manager"
    instance_template = google_compute_instance_template.disbursement_proxy_v2.self_link
  }

  auto_healing_policies {
    health_check      = google_compute_https_health_check.disbursement_proxy_v2.self_link
    initial_delay_sec = 300
  }
}

resource "google_compute_instance_template" "disbursement_proxy_v2" {
  name_prefix = "proxy-template-${var.client_name}"
  region      = var.region

  tags = [
    "disbursement-proxy-v2-${var.client_name}",
  ]

  instance_description = "Proxy for ${google_dns_record_set.disbursement_proxy_v2.name}"
  machine_type         = "f1-micro"

  labels = {
    environment = var.environment
  }

  disk {
    source_image = "projects/debian-cloud/global/images/family/debian-9"
    auto_delete  = true
    boot         = true
  }

  network_interface {
    network = "default"

    access_config {
      nat_ip = google_compute_address.disbursement_proxy_v2.address
    }
  }

  service_account {
    email = google_service_account.disbursement_proxy_v2.email

    // https://cloud.google.com/sdk/gcloud/reference/alpha/compute/instances/set-scopes#--scopes
    scopes = [
      "service-management",
      "service-control",
      "monitoring-write",
      "logging-write",
      "storage-ro",
      "compute-ro",
      "userinfo-email",
      "https://www.googleapis.com/auth/trace.append",
    ]
  }

  lifecycle {
    create_before_destroy = true
  }

  // This forces the instance to be recreated (thus re-running the script) if it is changed
  metadata_startup_script = <<EOF
#/bin/bash
# install packages to allow apt to use a repository over HTTPS:
sudo apt-get -y install ca-certificates software-properties-common

# build the caddyfile
# caddy proxy docs: https://caddyserver.com/docs/proxy
cat >Caddyfile <<EOL
${trim(google_dns_record_set.disbursement_proxy_v2.name, ".")}:443

log stdout
errors stderr

status 200 /healthz
forwardproxy {
    basicauth default-user Qklhjkdhf909-sdfkljhsdf  
    hide_ip
    hide_via
}
EOL

# build the systemd file
cat >/etc/systemd/system/caddy.service <<EOL
[Unit]
Description=Caddy HTTP/2 web server
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service
[Service]
Restart=on-abnormal

; Letsencrypt-issued certificates will be written to this directory.
Environment=CADDYPATH=/etc/ssl/caddy

ExecStart=/caddy/caddy -log=stdout -email=admin@brank.as -agree=true -conf=/Caddyfile -root=/var/tmp
ExecReload=/bin/kill -USR1 $MAINPID

; Use graceful shutdown with a reasonable timeout
KillMode=mixed
KillSignal=SIGQUIT
TimeoutStopSec=5s

; Limit the number of file descriptors; see 'man systemd.exec' for more limit settings.
LimitNOFILE=1048576
; Unmodified caddy is not expected to use more than that.
LimitNPROC=512

PrivateTmp=true
PrivateDevices=false
ProtectHome=true
ProtectSystem=full
ReadWriteDirectories=/etc/ssl/caddy

[Install]
WantedBy=multi-user.target
EOL

# Install the stackdriver agent
curl -sSO https://dl.google.com/cloudagents/install-logging-agent.sh
sudo bash install-logging-agent.sh

# Install caddy
mkdir caddy
wget https://github.com/vishen/caddy/releases/download/v0.11.0-forwardproxy/caddy_v0.11.0-forwardproxy.tar.gz
tar -xvzf caddy_v0.11.0-forwardproxy.tar.gz -C caddy

chmod 644 /etc/systemd/system/caddy.service
chmod 755 /caddy/caddy
mkdir -p /etc/ssl/caddy
systemctl daemon-reload
systemctl enable caddy.service
systemctl start caddy.service

    EOF
}

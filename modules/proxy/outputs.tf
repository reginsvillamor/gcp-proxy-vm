output "disbursement_proxy_v2_static_ip" {
  value = google_compute_address.disbursement_proxy_v2.address
}

output "disbursement_proxy_v2_domain" {
  value = trim(google_dns_record_set.disbursement_proxy_v2.name, ".")
}
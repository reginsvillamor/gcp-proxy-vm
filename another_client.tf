module "proxy_another_client" {
  source        = "./modules/proxy"
  client_name   = "client-2"
  environment   = "staging"
  dns_zone_name = "testzoneko-info"
  project_id    = var.project_id
  region        = var.region
  zone          = var.zone
}

output "proxy_another_client_domain_name" {
  value = module.proxy_another_client.disbursement_proxy_v2_domain
}

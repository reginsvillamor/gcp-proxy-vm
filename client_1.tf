module "proxy_client_1" {
  source        = "./modules/proxy"
  client_name   = "client-1"
  environment   = "staging"
  dns_zone_name = "testzoneko-info"
  project_id    = var.project_id
  region        = var.region
  zone          = var.zone
}

output "proxy_client_1_domain_name" {
  value = module.proxy_another_client.disbursement_proxy_v2_domain
}
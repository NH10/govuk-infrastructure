govuk_aws_state_bucket              = "govuk-terraform-steppingstone-test"
cluster_infrastructure_state_bucket = "govuk-terraform-test"

cluster_version               = 1.21
cluster_log_retention_in_days = 7

eks_control_plane_subnets = {
  a = { az = "eu-west-1a", cidr = "10.200.19.0/28" }
  b = { az = "eu-west-1b", cidr = "10.200.19.16/28" }
  c = { az = "eu-west-1c", cidr = "10.200.19.32/28" }
}

eks_public_subnets = {
  a = { az = "eu-west-1a", cidr = "10.200.20.0/24" }
  b = { az = "eu-west-1b", cidr = "10.200.21.0/24" }
  c = { az = "eu-west-1c", cidr = "10.200.22.0/24" }
}

eks_private_subnets = {
  a = { az = "eu-west-1a", cidr = "10.200.24.0/22" }
  b = { az = "eu-west-1b", cidr = "10.200.28.0/22" }
  c = { az = "eu-west-1c", cidr = "10.200.32.0/22" }
}

rabbitmq_subnets = {
  a = { az = "eu-west-1a", cidr = "10.200.36.0/28" }
  b = { az = "eu-west-1b", cidr = "10.200.36.16/28" }
  c = { az = "eu-west-1c", cidr = "10.200.36.32/28" }
}

govuk_environment = "test"
force_destroy     = true

publishing_service_domain = "test.publishing.service.gov.uk"
external_dns_subdomain    = "eks"

frontend_memcached_node_type   = "cache.t4g.micro"
shared_redis_cluster_node_type = "cache.t4g.small"

dex_github_orgs_teams = [{ name = "alphagov", teams = ["gov-uk", "gov-uk-production"] }]

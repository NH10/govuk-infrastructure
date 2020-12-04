terraform {
  backend "s3" {
    bucket  = "govuk-terraform-test"
    key     = "projects/publisher.tfstate"
    region  = "eu-west-1"
    encrypt = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.13"
    }
  }
}

provider "aws" {
  region = "eu-west-1"

  assume_role {
    role_arn = var.assume_role_arn
  }
}

# TODO - read these from remote state instead of using data sources
data "aws_secretsmanager_secret" "asset_manager_bearer_token" {
  name = "publisher_app-ASSET_MANAGER_BEARER_TOKEN"
}
data "aws_secretsmanager_secret" "fact_check_password" {
  name = "publisher_app-FACT_CHECK_PASSWORD"
}
data "aws_secretsmanager_secret" "fact_check_reply_to_address" {
  name = "publisher_app-FACT_CHECK_REPLY_TO_ADDRESS"
}
data "aws_secretsmanager_secret" "fact_check_reply_to_id" {
  name = "publisher_app-FACT_CHECK_REPLY_TO_ID"
}
data "aws_secretsmanager_secret" "govuk_notify_api_key" {
  name = "publisher_app-GOVUK_NOTIFY_API_KEY"
}
data "aws_secretsmanager_secret" "govuk_notify_template_id" {
  name = "publisher_app-GOVUK_NOTIFY_TEMPLATE_ID" # pragma: allowlist secret
}
data "aws_secretsmanager_secret" "jwt_auth_secret" {
  name = "publisher_app-JWT_AUTH_SECRET"
}
data "aws_secretsmanager_secret" "link_checker_api_bearer_token" {
  name = "publisher_app-LINK_CHECKER_API_BEARER_TOKEN"
}
data "aws_secretsmanager_secret" "link_checker_api_secret_token" {
  name = "publisher_app-LINK_CHECKER_API_SECRET_TOKEN"
}
data "aws_secretsmanager_secret" "mongodb_uri" {
  name = "publisher_app-MONGODB_URI"
}
data "aws_secretsmanager_secret" "oauth_id" {
  name = "publisher_app-OAUTH_ID"
}
data "aws_secretsmanager_secret" "oauth_secret" {
  name = "publisher_app-OAUTH_SECRET"
}
data "aws_secretsmanager_secret" "publishing_api_bearer_token" {
  name = "publisher_app-PUBLISHING_API_BEARER_TOKEN" # pragma: allowlist secret
}
data "aws_secretsmanager_secret" "secret_key_base" {
  name = "publisher_app-SECRET_KEY_BASE" # pragma: allowlist secret
}
data "aws_secretsmanager_secret" "sentry_dsn" {
  name = "SENTRY_DSN"
}

data "aws_iam_role" "execution" {
  name = "fargate_execution_role"
}

data "aws_iam_role" "task" {
  name = "fargate_task_role"
}

locals {
  # TODO - read these from remote state instead of using locals
  statsd_host                      = "statsd.${var.mesh_domain}"            # TODO: Put Statsd in App Mesh
  redis_port                       = 6379
  website_root                     = "https://frontend.${var.app_domain}"   # TODO: Change back to www once router is up
  assets_url                       = "https://static-ecs.${var.app_domain}"
  service_discovery_namespace_name = var.mesh_domain

  container_definition = {
    # TODO: factor out all the remaining hardcoded values (see ../content-store for an example where this has been done)
    "image" : "govuk/publisher:${var.image_tag}", # TODO: use deployed-to-production label or similar.
    "essential" : true,
    "environment" : [
      { "name" : "ASSET_HOST", "value" : local.assets_url },
      { "name" : "BASIC_AUTH_USERNAME", "value" : "gds" },
      { "name" : "EMAIL_GROUP_BUSINESS", "value" : "test-address@digital.cabinet-office.gov.uk" },
      { "name" : "EMAIL_GROUP_CITIZEN", "value" : "test-address@digital.cabinet-office.gov.uk" },
      { "name" : "EMAIL_GROUP_DEV", "value" : "test-address@digital.cabinet-office.gov.uk" },
      { "name" : "EMAIL_GROUP_FORCE_PUBLISH_ALERTS", "value" : "test-address@digital.cabinet-office.gov.uk" },
      { "name" : "FACT_CHECK_SUBJECT_PREFIX", "value" : "dev" },
      { "name" : "FACT_CHECK_USERNAME", "value" : "govuk-fact-check-test@digital.cabinet-office.gov.uk" },
      { "name" : "GOVUK_APP_DOMAIN", "value" : local.service_discovery_namespace_name },
      { "name" : "GOVUK_APP_DOMAIN_EXTERNAL", "value" : var.app_domain },
      { "name" : "GOVUK_APP_NAME", "value" : "publisher" },
      { "name" : "GOVUK_APP_ROOT", "value" : "/app" },
      { "name" : "GOVUK_APP_TYPE", "value" : "rack" },
      { "name" : "GOVUK_STATSD_PREFIX", "value" : "fargate" },
      # TODO: how does GOVUK_ASSET_ROOT relate to ASSET_HOST? Is one a function of the other? Are they both really in use? Is GOVUK_ASSET_ROOT always just "https://${ASSET_HOST}"?
      { "name" : "GOVUK_ASSET_ROOT", "value" : "https://assets.test.publishing.service.gov.uk" },
      { "name" : "GOVUK_GROUP", "value" : "deploy" },
      { "name" : "GOVUK_USER", "value" : "deploy" },
      { "name" : "GOVUK_WEBSITE_ROOT", "value" : local.website_root },
      { "name" : "PLEK_SERVICE_CONTENT_STORE_URI", "value" : "https://www.gov.uk/api" }, # TODO: looks suspicious
      { "name" : "PLEK_SERVICE_PUBLISHING_API_URI", "value" : "http://publishing-api-web.${local.service_discovery_namespace_name}" },
      { "name" : "PLEK_SERVICE_SIGNON_URI", "value" : "https://signon-ecs.${var.app_domain}" },
      { "name" : "PLEK_SERVICE_STATIC_URI", "value" : "https://assets.test.publishing.service.gov.uk" },
      # TODO: remove PLEK_SERVICE_DRAFT_ORIGIN_URI once we have the draft origin properly set up with multiple frontends
      { "name" : "PLEK_SERVICE_DRAFT_ORIGIN_URI", "value" : "https://draft-frontend.${var.app_domain}" },
      { "name" : "PORT", "value" : "80" },
      { "name" : "RAILS_ENV", "value" : "production" },
      { "name" : "RAILS_SERVE_STATIC_FILES", "value" : "true" }, # TODO: temporary hack?
      # TODO: we shouldn't be specifying both REDIS_{HOST,PORT} *and* REDIS_URL.
      { "name" : "REDIS_HOST", "value" : var.redis_host },
      { "name" : "REDIS_PORT", "value" : tostring(local.redis_port) },
      { "name" : "REDIS_URL", "value" : "redis://${var.redis_host}:${local.redis_port}" },
      { "name" : "STATSD_PROTOCOL", "value" : "tcp" },
      { "name" : "STATSD_HOST", "value" : local.statsd_host },
      { "name" : "WEBSITE_ROOT", "value" : local.website_root },
      { "name" : "SENTRY_ENVIRONMENT", "value" : var.sentry_environment }
    ],
    "dependsOn" : [{
      "containerName" : "envoy",
      "condition" : "START"
    }],
    "logConfiguration" : {
      "logDriver" : "awslogs",
      "options" : {
        "awslogs-create-group" : "true",
        "awslogs-group" : "awslogs-fargate",
        "awslogs-region" : "eu-west-1", # TODO: hardcoded region
        "awslogs-stream-prefix" : "awslogs-publisher"
      }
    },
    "mountPoints" : [],
    "portMappings" : [
      {
        "containerPort" : 80,
        "hostPort" : 80,
        "protocol" : "tcp"
      }
    ],
    "secrets" : [
      {
        "name" : "ASSET_MANAGER_BEARER_TOKEN",
        "valueFrom" : data.aws_secretsmanager_secret.asset_manager_bearer_token.arn
      },
      {
        "name" : "FACT_CHECK_PASSWORD",
        "valueFrom" : data.aws_secretsmanager_secret.fact_check_password.arn
      },
      {
        "name" : "FACT_CHECK_REPLY_TO_ADDRESS",
        "valueFrom" : data.aws_secretsmanager_secret.fact_check_reply_to_address.arn
      },
      {
        "name" : "FACT_CHECK_REPLY_TO_ID",
        "valueFrom" : data.aws_secretsmanager_secret.fact_check_reply_to_id.arn
      },
      {
        "name" : "GOVUK_NOTIFY_API_KEY",
        "valueFrom" : data.aws_secretsmanager_secret.govuk_notify_api_key.arn
      },
      {
        "name" : "GOVUK_NOTIFY_TEMPLATE_ID",
        "valueFrom" : data.aws_secretsmanager_secret.govuk_notify_template_id.arn
      },
      {
        "name" : "JWT_AUTH_SECRET",
        "valueFrom" : data.aws_secretsmanager_secret.jwt_auth_secret.arn
      },
      {
        "name" : "LINK_CHECKER_API_BEARER_TOKEN",
        "valueFrom" : data.aws_secretsmanager_secret.link_checker_api_bearer_token.arn
      },
      {
        "name" : "LINK_CHECKER_API_SECRET_TOKEN",
        "valueFrom" : data.aws_secretsmanager_secret.link_checker_api_secret_token.arn
      },
      {
        # TODO: Only the password should be a secret in the MONGODB_URI.
        "name" : "MONGODB_URI",
        "valueFrom" : data.aws_secretsmanager_secret.mongodb_uri.arn
      },
      {
        "name" : "GDS_SSO_OAUTH_ID",
        "valueFrom" : data.aws_secretsmanager_secret.oauth_id.arn
      },
      {
        "name" : "GDS_SSO_OAUTH_SECRET",
        "valueFrom" : data.aws_secretsmanager_secret.oauth_secret.arn
      },
      {
        "name" : "PUBLISHING_API_BEARER_TOKEN",
        "valueFrom" : data.aws_secretsmanager_secret.publishing_api_bearer_token.arn
      },
      {
        "name" : "SECRET_KEY_BASE",
        "valueFrom" : data.aws_secretsmanager_secret.secret_key_base.arn
      },
      {
        "name" : "SENTRY_DSN",
        "valueFrom" : data.aws_secretsmanager_secret.sentry_dsn.arn
      }
    ]
  }
}

module "envoy_settings_web" {
  source       = "../../../modules/envoy-settings"
  mesh_name    = var.mesh_name
  service_name = "publisher-web"
}

module "envoy_settings_worker" {
  source       = "../../../modules/envoy-settings"
  mesh_name    = var.mesh_name
  service_name = "publisher-worker"
}

resource "aws_ecs_task_definition" "web" {
  family                   = "publisher-web"
  requires_compatibilities = ["FARGATE"]
  container_definitions    = jsonencode([
    merge(
      local.container_definition,
      { name: "publisher-web" }
    ),
    module.envoy_settings_web.container_definition
  ])

  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  task_role_arn            = data.aws_iam_role.task.arn
  execution_role_arn       = data.aws_iam_role.execution.arn

  proxy_configuration {
    type           = "APPMESH"
    container_name = "envoy"

    properties = {
      AppPorts         = "80"
      EgressIgnoredIPs = module.envoy_settings_web.egress_ignored_ips
      IgnoredUID       = module.envoy_settings_web.ignored_uid
      ProxyEgressPort  = module.envoy_settings_web.proxy_egress_port
      ProxyIngressPort = module.envoy_settings_web.proxy_ingress_port
    }
  }
}

resource "aws_ecs_task_definition" "worker" {
  family                   = "publisher-worker"
  requires_compatibilities = ["FARGATE"]
  container_definitions    = jsonencode([
    merge(
      local.container_definition,
      {
        name: "publisher-worker" ,
        command: ["foreman", "run", "worker"]
      }
    ),
    module.envoy_settings_worker.container_definition
  ])

  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  task_role_arn            = data.aws_iam_role.task.arn
  execution_role_arn       = data.aws_iam_role.execution.arn

  proxy_configuration {
    type           = "APPMESH"
    container_name = "envoy"

    properties = {
      AppPorts         = "80"
      EgressIgnoredIPs = module.envoy_settings_worker.egress_ignored_ips
      IgnoredUID       = module.envoy_settings_worker.ignored_uid
      ProxyEgressPort  = module.envoy_settings_worker.proxy_egress_port
      ProxyIngressPort = module.envoy_settings_worker.proxy_ingress_port
    }
  }
}

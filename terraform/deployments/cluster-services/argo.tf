# Installs and configures ArgoCD for deploying GOV.UK apps
locals {
  argo_host           = "argo.${local.external_dns_zone_name}"
  argo_workflows_host = "argo-workflows.${local.external_dns_zone_name}"
}

resource "helm_release" "argo_cd" {
  chart      = "argo-cd"
  name       = "argo-cd"
  namespace  = local.services_ns
  repository = "https://argoproj.github.io/argo-helm"
  version    = "3.32.1" # TODO: Dependabot or equivalent so this doesn't get neglected.
  values = [yamlencode({
    global = {
      image = { # TODO: remove this section when v2.3.0 is released and includes fix: https://github.com/argoproj/argo-cd/pull/8350
        repository = "quay.io/argoproj/argocd"
        tag        = "v2.3.0-rc5"
      }
    }

    server = {
      # TLS Termination happens at the ALB, the insecure flag prevents Argo
      # server from upgrading the request after TLS termination.
      extraArgs = ["--insecure"]

      ingress = {
        enabled = true
        annotations = {
          "alb.ingress.kubernetes.io/group.name"         = "argo"
          "alb.ingress.kubernetes.io/scheme"             = "internet-facing"
          "alb.ingress.kubernetes.io/target-type"        = "ip"
          "alb.ingress.kubernetes.io/load-balancer-name" = "argo"
          "alb.ingress.kubernetes.io/listen-ports"       = jsonencode([{ "HTTP" : 80 }, { "HTTPS" : 443 }])
          "alb.ingress.kubernetes.io/ssl-redirect"       = "443"
        }
        labels           = {}
        ingressClassName = "aws-alb"
        hosts            = [local.argo_host]
        https            = true
      }

      config = {
        url = "https://${local.argo_host}"

        "oidc.config" = yamlencode({
          name         = "GitHub"
          issuer       = "https://${local.dex_host}"
          clientID     = "$govuk-dex-argocd:clientID"
          clientSecret = "$govuk-dex-argocd:clientSecret"
        })
      }

      rbacConfig = {
        # TODO: all logged in users are admin, maybe we want differentiation
        "policy.default" = "role:admin"
      }

      ingressGrpc = {
        enabled  = true
        isAWSALB = true
        annotations = {
          "alb.ingress.kubernetes.io/group.name"         = "argo"
          "alb.ingress.kubernetes.io/scheme"             = "internet-facing"
          "alb.ingress.kubernetes.io/target-type"        = "ip"
          "alb.ingress.kubernetes.io/load-balancer-name" = "argo"
          "alb.ingress.kubernetes.io/listen-ports"       = jsonencode([{ "HTTP" : 80 }, { "HTTPS" : 443 }])
          "alb.ingress.kubernetes.io/ssl-redirect"       = "443"
        }
        labels           = {}
        ingressClassName = "aws-alb"
        hosts            = [local.argo_host]
        https            = true
      }
    }

    dex = {
      enabled = false
    }
  })]
}

resource "helm_release" "argo_services" {
  # Relies on CRDs
  depends_on = [helm_release.argo_cd, helm_release.argo_events]
  chart      = "argo-services"
  name       = "argo-services"
  namespace  = local.services_ns
  repository = "https://alphagov.github.io/govuk-helm-charts/"
  version    = "0.1.3" # TODO: Dependabot or equivalent so this doesn't get neglected.
  values = [yamlencode({
    # TODO: This TF module should not need to know the govuk_environment, since
    # there is only one per AWS account.
    govukEnvironment = var.govuk_environment
    argocdUrl        = "https://${local.argo_host}"
  })]
}

resource "helm_release" "argo_notifications" {
  chart      = "argocd-notifications"
  name       = "argocd-notifications"
  namespace  = local.services_ns
  repository = "https://argoproj.github.io/argo-helm"
  version    = "1.5.1" # TODO: Dependabot or equivalent so this doesn't get neglected.
  values = [yamlencode({
    # Configured in argo-services Helm chart
    cm = {
      create = false
    }
    "argocdUrl" = "https://${local.argo_host}"

    # argocd-notifications-secret will be created by ExternalSecrets
    # since the secrets are stored in AWS SecretsManager
    secret = {
      create = false
    }
  })]
}

resource "kubernetes_namespace_v1" "apps" {
  for_each = toset(var.argo_workflows_namespaces)
  metadata {
    name = each.value
  }
}

resource "helm_release" "argo_workflows" {
  # Dex is used to provide SSO facility to Argo-Workflows and there is a bug
  # where Argo Workflows fail to start if Dex is not present
  depends_on = [helm_release.dex]
  chart      = "argo-workflows"
  name       = "argo-workflows"
  depends_on = [kubernetes_namespace_v1.apps]
  namespace  = local.services_ns
  repository = "https://argoproj.github.io/argo-helm"
  version    = "0.9.5" # TODO: Dependabot or equivalent so this doesn't get neglected.
  values = [yamlencode({
    controller = {
      workflowNamespaces = concat([local.services_ns], var.argo_workflows_namespaces)
      workflowDefaults = {
        spec = {
          activeDeadlineSeconds = 7200
          ttlStrategy = {
            secondsAfterSuccess = 432000
          }
          podGC = {
            strategy = "OnWorkflowSuccess"
          }
        }
      }
    }

    workflow = {
      serviceAccount = {
        create = true
      }
    }

    server = {
      extraArgs = ["--auth-mode=client", "--auth-mode=sso"]
      ingress = {
        enabled = true
        annotations = {
          "alb.ingress.kubernetes.io/group.name"         = "argo-workflows"
          "alb.ingress.kubernetes.io/scheme"             = "internet-facing"
          "alb.ingress.kubernetes.io/target-type"        = "ip"
          "alb.ingress.kubernetes.io/load-balancer-name" = "argo-workflows"
          "alb.ingress.kubernetes.io/listen-ports"       = jsonencode([{ "HTTP" : 80 }, { "HTTPS" : 443 }])
          "alb.ingress.kubernetes.io/ssl-redirect"       = "443"
        }
        ingressClassName = "aws-alb"
        hosts            = [local.argo_workflows_host]
      }
      sso = {
        issuer = "https://${local.dex_host}"
        clientId = {
          name = "govuk-dex-argo-workflows"
          key  = "clientID"
        }
        clientSecret = {
          name = "govuk-dex-argo-workflows"
          key  = "clientSecret"
        }
        redirectUrl = "https://${local.argo_workflows_host}/oauth2/callback"
        # TODO: all logged in users are admin, maybe we want differentiation
      }

    }
  })]
}

resource "helm_release" "argo_events" {
  chart      = "argo-events"
  name       = "argo-events"
  namespace  = local.services_ns
  repository = "https://argoproj.github.io/argo-helm"
  version    = "1.7.0" # TODO: Dependabot or equivalent so this doesn't get neglected.
  values = [yamlencode({
    namespace = local.services_ns
  })]
}

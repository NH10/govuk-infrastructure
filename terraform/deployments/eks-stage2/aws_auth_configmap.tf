# Generate the aws-auth ConfigMap, which defines the mapping between AWS IAM
# roles and k8s RBAC. The authoritative ACLs are defined in
# https://github.com/alphagov/govuk-aws-data/blob/master/data/infra-security/
# and read here via Terraform remote state.
#
# The aws-auth ConfigMap is documented at
# https://docs.aws.amazon.com/eks/latest/userguide/add-user-role.html
#
# Generally, it is unwise to manage k8s objects directly from Terraform (as
# opposed to using Helm or kubectl or other tooling designed to work with
# k8s). This is a rare exception to that rule of thumb.

locals {
  default_configmap_roles = [
    {
      rolearn  = data.terraform_remote_state.eks.outputs.worker_iam_role_arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups   = ["system:bootstrappers", "system:nodes"]
    },
  ]

  concourse_worker_role = {
    "govuk-concourse-deployer" = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/govuk-concourse-deployer"
  }

  admin_roles_and_arns = merge(data.terraform_remote_state.infra_security.outputs.admin_roles_and_arns, local.concourse_worker_role)
  admin_configmap_roles = [
    for user, arn in local.admin_roles_and_arns : {
      rolearn  = arn
      username = user
      # TODO: don't use system:masters.
      groups = ["system:masters"]
    }
  ]
}

resource "kubernetes_config_map" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
    labels    = { "app.kubernetes.io/managed-by" = "Terraform" }
  }

  data = {
    mapRoles = yamlencode(
      distinct(concat(
        local.default_configmap_roles,
        local.admin_configmap_roles,
      ))
    )
  }
}

data "aws_secretsmanager_secret" "opensearch_credentials" {
  count = var.secret_name != null ? 1 : 0
  name  = var.secret_name
}

data "aws_secretsmanager_secret_version" "current" {
  count     = var.secret_name != null ? 1 : 0
  secret_id = data.aws_secretsmanager_secret.opensearch_credentials[0].id
}


locals {
  default_aggregator_template_variables = {
    queue_url        = module.vector_sqs.queue_id,
    endpoint         = var.elasticsearch_endpoint,
    region           = data.aws_region.current.id,
    eks_cluster_name = var.eks_cluster_name
  }
  custom_aggregator_config = templatefile(var.aggregator_template_filename, merge(local.default_aggregator_template_variables, var.aggregator_template_variables))

  aggregator_values = {
    role = "Aggregator"
    serviceAccount = {
      annotations = {
        "eks.amazonaws.com/role-arn" = module.vector_aggregator_role.arn
      }
    }
  }

  basic_settings = [
    { name = "customConfig.sinks.opensearch.auth.strategy", value = "basic" },
    { name = "customConfig.sinks.opensearch.auth.user", value = try(jsondecode(data.aws_secretsmanager_secret_version.current[0].secret_string)["vector_username"], "") }
  ]
  basic_sensitive = [
    { name = "customConfig.sinks.opensearch.auth.password", value = try(jsondecode(data.aws_secretsmanager_secret_version.current[0].secret_string)["vector_password"], "") }
  ]
  basic_auth_settings  = var.secret_name == null ? [] : local.basic_settings
  basic_auth_sensitive = var.secret_name == null ? [] : local.basic_sensitive
}

data "utils_deep_merge_yaml" "values_aggregator_merged" {
  input = [
    local.custom_aggregator_config,
    yamlencode(local.aggregator_values),
    yamlencode(try(var.aggregator_values_override, {}))
  ]
}

resource "helm_release" "vector_aggregator" {
  name             = "vector-aggregator"
  chart            = local.helm_chart_config.chart
  repository       = local.helm_chart_config.repository
  version          = local.helm_chart_config.version
  namespace        = local.helm_chart_config.namespace
  create_namespace = local.helm_chart_config.create_namespace

  values = [data.utils_deep_merge_yaml.values_aggregator_merged.output]

  set = [
    for item in local.basic_auth_settings : {
      name  = item.name
      value = item.value
    }
  ]
  set_sensitive = [
    for item in local.basic_auth_sensitive : {
      name  = item.name
      value = item.value
    }
  ]
}

data "aws_iam_policy_document" "vector_aggregator" {
  statement {
    actions = [
      "sqs:DeleteMessage",
      "sqs:ReceiveMessage"
    ]
    resources = [
      module.vector_sqs.queue_arn
    ]
    effect = "Allow"
  }

  statement {
    actions = [
      "s3:GetObject"
    ]
    resources = [
      "${module.vector_s3_bucket.s3_bucket_arn}/*"
    ]
    effect = "Allow"
  }
}

resource "aws_iam_policy" "vector_aggregator" {
  name        = "${data.aws_eks_cluster.eks.id}-vector-aggregator"
  path        = "/"
  description = "Policy for vector aggregator pod."

  policy = data.aws_iam_policy_document.vector_aggregator.json
  tags   = var.tags
}

module "vector_aggregator_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "6.2.3"

  name        = "${data.aws_eks_cluster.eks.name}-vector-aggregator"
  description = "Vector Aggregator IRSA"

  # Enable OIDC provider trust
  enable_oidc        = true
  oidc_provider_urls = [replace(data.aws_eks_cluster.eks.identity[0].oidc[0].issuer, "https://", "")]
  oidc_subjects      = ["system:serviceaccount:${local.helm_chart_config.namespace}:vector-aggregator"]
  oidc_audiences     = ["sts.amazonaws.com"]

  # Attach policies
  policies = {
    vector_aggregator = aws_iam_policy.vector_aggregator.arn
  }

  tags = var.tags
}

variable "name" {
  description = "Cluster name. Example: dev-tecso"
  type        = string
}

#### EKS CLUSTER

variable "vpc_id" {
  description = "VPC ID where the cluster will be deployed"
  type        = string
}

variable "subnets_private_ids" {
  description = "Private subnet IDs for the cluster control plane endpoints and node groups"
  type        = list(string)
}

variable "eks_version" {
  description = "Kubernetes version. Example: 1.33"
  type        = string
}

variable "endpoint_private_access" {
  description = "Enable private API server endpoint"
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Enable public API server endpoint"
  type        = bool
  default     = false
}

variable "kubernetes_service_ipv4_cidr" {
  description = "Internal Kubernetes service CIDR block"
  type        = string
  default     = "172.20.0.0/16"
}

variable "cidr_blocks_sg_master" {
  description = "CIDR blocks allowed ingress access to the cluster and nodes security group"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection on the EKS cluster. Prevents accidental deletion via the AWS Console or API. Requires AWS provider >= 6.9.0."
  type        = bool
  default     = true
}

#### CLUSTER ACCESS

variable "cluster_admin_role_arns" {
  description = <<-EOT
    List of IAM role ARNs granted full cluster admin access (AmazonEKSClusterAdminPolicy).
    Authentication mode is set to API_AND_CONFIG_MAP.

    Example:
      cluster_admin_role_arns = [
        "arn:aws:iam::ACCOUNT_ID:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_<PermissionSetId>",
      ]
  EOT
  type        = list(string)
  default     = []
}

variable "cluster_poweruser_role_arns" {
  description = <<-EOT
    List of IAM role ARNs granted admin access scoped to workloads (AmazonEKSAdminPolicy).
    Can manage deployments, services, configmaps and RBAC within namespaces, but cannot manage nodes or cluster-level configuration.

    Example:
      cluster_poweruser_role_arns = [
        "arn:aws:iam::ACCOUNT_ID:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_PowerUserAccess_<PermissionSetId>",
      ]
  EOT
  type        = list(string)
  default     = []
}

variable "cluster_readonly_role_arns" {
  description = <<-EOT
    List of IAM role ARNs granted read-only cluster access (AmazonEKSViewPolicy).

    Example:
      cluster_readonly_role_arns = [
        "arn:aws:iam::ACCOUNT_ID:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_ReadOnlyAccess_<PermissionSetId>",
      ]
  EOT
  type        = list(string)
  default     = []
}

#### EKS NODES

variable "nodes_groups" {
  description = <<-EOT
    Map of node group configurations. Map key is used as the internal for_each key.
    `ng_iam_policy` is REQUIRED: it is a custom IAM policy ARN attached only to
    that node group's IAM role (each node group gets its own role). If the group
    needs no extra permissions, pass an empty policy.
    `ng_key_name` is optional: nodes are reachable via SSM Session Manager
    without an SSH key.

    Example:
      nodes_groups = {
        main = {
          ng_name          = "main"
          ng_subnets       = [module.vpc.private_subnet_ids["1a"]]
          ng_as_desired    = 2
          ng_as_min        = 1
          ng_as_max        = 3
          ng_instance_type = "t3a.medium"
          ng_key_name      = "my-key"
          ng_volume_size   = "50"
          ng_iam_policy    = aws_iam_policy.nodegroup_main.arn
        }
      }
  EOT
  type = map(object({
    ng_name          = string
    ng_subnets       = list(string)
    ng_as_desired    = number
    ng_as_min        = number
    ng_as_max        = number
    ng_instance_type = string
    ng_key_name      = optional(string)
    ng_volume_size   = string
    ng_iam_policy    = string
  }))
}

variable "tags" {
  description = "Additional tags applied to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_prefix_delegation" {
  description = "Enable VPC CNI prefix delegation. Allows ~110 pods per node instead of ~35 by reserving /28 IP blocks."
  type        = string
  default     = "true"
}

# terraform-aws-eks

Terraform module that deploys an Amazon EKS cluster with managed node groups,
essential add-ons and IAM configuration. It creates the control plane, its
security group and IAM role, the worker node IAM role (with the AWS Load
Balancer Controller and Cluster Autoscaler policies), managed node groups via
launch templates, cluster access entries (admin / poweruser / read-only) and the
core EKS add-ons (`coredns`, `kube-proxy`, `vpc-cni`, `aws-ebs-csi-driver`).

Designed to be used together with the `terraform-aws-vpc` module, consuming its
outputs (`vpc_id`, `private_subnet_ids`, `public_subnet_ids`).

## Requirements

| Name      | Version   |
|-----------|-----------|
| terraform | >= 1.3.7  |
| aws       | >= 6.9.0  |

> [!note]
> AWS provider `>= 6.9.0` is required because `aws_eks_cluster` gained the
> `deletion_protection` argument in that release.

## Subnet tagging for the AWS Load Balancer Controller

Subnets must be tagged so the Load Balancer Controller can discover them.

Public subnets:

```hcl
tags = {
  "kubernetes.io/role/elb"                 = "1"
  "kubernetes.io/cluster/<CLUSTER_NAME>"   = "shared"
}
```

Private subnets:

```hcl
tags = {
  "kubernetes.io/role/internal-elb"        = "1"
  "kubernetes.io/cluster/<CLUSTER_NAME>"   = "shared"
}
```

## Usage

```hcl
# Tag the VPC subnets so the AWS Load Balancer Controller can discover them.
# The terraform-aws-vpc module sets ignore_changes = [tags], so tagging the
# subnets externally with aws_ec2_tag does not conflict.
resource "aws_ec2_tag" "public_subnet_elb" {
  for_each    = toset(module.vpc.public_subnet_ids_list)
  resource_id = each.value
  key         = "kubernetes.io/role/elb"
  value       = "1"
}

resource "aws_ec2_tag" "private_subnet_internal_elb" {
  for_each    = toset(module.vpc.private_subnet_ids_list)
  resource_id = each.value
  key         = "kubernetes.io/role/internal-elb"
  value       = "1"
}

resource "aws_ec2_tag" "public_subnet_cluster" {
  for_each    = toset(module.vpc.public_subnet_ids_list)
  resource_id = each.value
  key         = "kubernetes.io/cluster/my-cluster"
  value       = "shared"
}

resource "aws_ec2_tag" "private_subnet_cluster" {
  for_each    = toset(module.vpc.private_subnet_ids_list)
  resource_id = each.value
  key         = "kubernetes.io/cluster/my-cluster"
  value       = "shared"
}

module "eks" {
  source  = "tecsocoop/eks/aws"
#  version = "X.X.X" # see the latest available tag

  name        = "my-cluster"
  eks_version = "1.33" # see the latest available version in the AWS console

  vpc_id              = module.vpc.vpc_id
  subnets_private_ids = module.vpc.private_subnet_ids_list

  # Deletion protection (enabled by default)
  enable_deletion_protection = true

  # Cluster access — full admin roles (API + ConfigMap auth mode)
  cluster_admin_role_arns = [
    "arn:aws:iam::ACCOUNT_ID:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_<PermissionSetId>",
  ]

  # Cluster access — workload admin roles
  cluster_poweruser_role_arns = [
    "arn:aws:iam::ACCOUNT_ID:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_PowerUserAccess_<PermissionSetId>",
  ]

  # Cluster access — read-only roles
  cluster_readonly_role_arns = [
    "arn:aws:iam::ACCOUNT_ID:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_ReadOnlyAccess_<PermissionSetId>",
  ]

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
      ng_iam_policy    = aws_iam_policy.nodegroup_main.arn # full ECR access
    }
    secondary = {
      ng_name          = "secondary"
      ng_subnets       = [module.vpc.private_subnet_ids["1b"]]
      ng_as_desired    = 1
      ng_as_min        = 1
      ng_as_max        = 2
      ng_instance_type = "t3a.small"
      ng_volume_size   = "50" # no ng_key_name: reachable via SSM only
      ng_iam_policy    = aws_iam_policy.nodegroup_secondary.arn # prd-example backup
    }
  }

  tags_additional = {
    "Environment" = "production"
  }
}

# Custom per-node-group IAM policies (inline).
# main node group -> full ECR access.
resource "aws_iam_policy" "nodegroup_main" {
  name = "nodegroup-main"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ecr:*"
        Resource = "*"
      },
    ]
  })
}

# secondary node group -> read/write access to the prd-example backup bucket.
resource "aws_iam_policy" "nodegroup_secondary" {
  name = "nodegroup-secondary"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
        ]
        Resource = [
          "arn:aws:s3:::prd-example",
          "arn:aws:s3:::prd-example/*",
        ]
      },
    ]
  })
}
```

> [!note]
> Cluster access is granted at the **IAM role** level, not per individual user.
> Authentication mode is `API_AND_CONFIG_MAP`. Every SSO user assuming a granted
> role inherits its permissions automatically.
> The `<PermissionSetId>` suffix is a unique hex ID AWS generates per account.
> Retrieve it with:
> ```bash
> aws iam list-roles \
>   --query "Roles[?contains(RoleName, 'AWSReservedSSO')].Arn" --output table
> ```

### Cluster access levels

| Variable                     | EKS policy                    | Capabilities                                                                                   |
|------------------------------|-------------------------------|------------------------------------------------------------------------------------------------|
| `cluster_admin_role_arns`    | `AmazonEKSClusterAdminPolicy` | Full cluster admin (equivalent to `cluster-admin` RBAC). Manages nodes, namespaces, RBAC, config. |
| `cluster_poweruser_role_arns`    | `AmazonEKSAdminPolicy`        | Workload admin. Manages deployments, services, configmaps and RBAC within namespaces.          |
| `cluster_readonly_role_arns` | `AmazonEKSViewPolicy`         | Read-only access to all cluster resources.                                                     |

### Node access via SSM Session Manager

Nodes get the `AmazonSSMManagedInstanceCore` policy and the SSM agent is
preinstalled on the EKS-optimized AMI, so they are reachable via AWS Systems
Manager Session Manager without an SSH key (`ng_key_name` is optional). Connect
from the AWS console (Systems Manager > Session Manager) or the CLI:

```bash
aws ssm start-session --target <instance_id>
```

List the node instance IDs of the cluster:

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Cluster,Values=my-cluster" \
  --query "Reservations[].Instances[].InstanceId" --output text
```

Requires the Session Manager plugin for the AWS CLI:
https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html

### Optional add-on: EFS CSI

If EFS support is required, add these resources in the root module. The EFS CSI
driver policy is attached to every node group role via `node_role_names`:

```hcl
resource "aws_eks_addon" "efs_csi" {
  cluster_name = module.eks.cluster_name
  addon_name   = "aws-efs-csi-driver"
}

resource "aws_iam_role_policy_attachment" "efs_csi" {
  for_each   = module.eks.node_role_names
  role       = each.value
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
}
```

<details>
<summary>Variables</summary>

| Variable                           | Description                                                             | Values                | Default              |
|------------------------------------|-------------------------------------------------------------------------|-----------------------|----------------------|
| `name`                             | Cluster name.                                                           | string - e.g. `my-cluster` | -               |
| `eks_version`                      | Kubernetes version.                                                     | string - e.g. `1.33`  | -                    |
| `vpc_id`                           | VPC ID where the cluster is deployed.                                   | string                | -                    |
| `subnets_private_ids`              | Private subnet IDs for the control plane and node groups.              | `list(string)`        | -                    |
| `endpoint_private_access`          | Enable the private API server endpoint.                               | bool                  | `true`               |
| `endpoint_public_access`           | Enable the public API server endpoint.                                | bool                  | `false`              |
| `kubernetes_service_ipv4_cidr`     | Internal Kubernetes service CIDR block.                               | string                | `172.20.0.0/16`      |
| `cidr_blocks_sg_master`            | CIDRs allowed ingress to the cluster/nodes security group.           | `list(string)`        | `["0.0.0.0/0"]`      |
| `enable_deletion_protection`       | Protect the cluster against accidental deletion.                      | bool                  | `true`               |
| `cluster_admin_role_arns`          | IAM role ARNs with full cluster admin access.                        | `list(string)`        | `[]`                 |
| `cluster_poweruser_role_arns`          | IAM role ARNs with workload admin access.                            | `list(string)`        | `[]`                 |
| `cluster_readonly_role_arns`       | IAM role ARNs with read-only access.                                 | `list(string)`        | `[]`                 |
| `nodes_groups`                     | Map of node group configurations (see keys below).                   | `map(object)`         | -                    |
| `enable_prefix_delegation`         | Enable VPC CNI prefix delegation (~110 pods/node instead of ~35).    | string                | `"true"`             |
| `tags_additional`                  | Additional tags applied to all resources.                            | `map(string)`         | `{}`                 |

`nodes_groups` object keys:

| Key                | Description                              | Values                        |
|--------------------|------------------------------------------|-------------------------------|
| `ng_name`          | Node group name suffix.                  | string - e.g. `main`          |
| `ng_subnets`       | Subnet IDs for this node group.          | `list(string)`                |
| `ng_as_desired`    | Desired instance count in the ASG.       | number                        |
| `ng_as_min`        | Minimum instance count in the ASG.       | number                        |
| `ng_as_max`        | Maximum instance count in the ASG.       | number                        |
| `ng_instance_type` | EC2 instance type.                       | string - e.g. `t3a.medium`    |
| `ng_key_name`      | SSH key pair name (optional; nodes are reachable via SSM).             | string (optional)             |
| `ng_volume_size`   | Root EBS volume size in GB (gp3).        | string - e.g. `50`            |
| `ng_iam_policy`    | **Required** custom IAM policy ARN attached only to this node group's role (pass an empty policy if none needed). | string - policy ARN |

</details>

<details>
<summary>Outputs</summary>

| Output                               | Description                                                    |
|--------------------------------------|----------------------------------------------------------------|
| `cluster_name`                       | EKS cluster name.                                              |
| `cluster_arn`                        | EKS cluster ARN.                                               |
| `cluster_endpoint`                   | Endpoint of the Kubernetes API server.                        |
| `cluster_version`                    | Kubernetes version running on the cluster.                    |
| `cluster_certificate_authority_data` | Base64-encoded certificate authority data.                    |
| `cluster_oidc_issuer_url`            | OIDC issuer URL of the cluster (for IRSA).                     |
| `cluster_security_group_id`          | ID of the cluster/nodes security group.                       |
| `cluster_role_arn`                   | ARN of the control-plane IAM role.                            |
| `node_role_arns`                     | Map `node group key => worker node IAM role ARN`.             |
| `node_role_names`                    | Map `node group key => worker node IAM role name`.            |
| `node_groups`                        | Map of created node groups (name, ARN, status).              |

</details>

## Notes

### VPC CNI prefix delegation

When `enable_prefix_delegation = "true"` (default), the VPC CNI reserves `/28`
blocks (16 contiguous IPs) instead of individual IPs, allowing roughly **110
pods per node** instead of ~35. Applied automatically:

```
ENABLE_PREFIX_DELEGATION = "true"
WARM_PREFIX_TARGET       = "1"
```

When enabling prefix delegation for the first time, existing nodes must be
recreated to pick up the new CNI configuration:

```bash
terraform apply -replace='module.eks.aws_eks_node_group.main["main"]'
```

### Per-node-group IAM policies (`ng_iam_policy`)

Each node group gets its **own IAM role**, so different node groups can be
granted different permissions. `ng_iam_policy` is required per node group; pass
an empty policy if a group needs no extra permissions. See the `Usage` example.

## License

Licensed under the [Apache License 2.0](LICENSE).

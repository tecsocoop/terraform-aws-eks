######## CLUSTER

resource "aws_eks_cluster" "main" {
  name     = var.name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.eks_version

  deletion_protection = var.enable_deletion_protection

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = var.subnets_private_ids
    security_group_ids      = [aws_security_group.eks.id]
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
  }

  kubernetes_network_config {
    service_ipv4_cidr = var.kubernetes_service_ipv4_cidr
  }

  depends_on = [
    aws_iam_role_policy_attachment.AmazonEKSClusterPolicy
  ]

  tags = merge(
    var.tags,
    {
      "Cluster" = var.name
    },
  )
}

######## CLUSTER ACCESS ENTRIES

# Admin roles — full cluster admin access (AmazonEKSClusterAdminPolicy)
resource "aws_eks_access_entry" "admin" {
  for_each      = toset(var.cluster_admin_role_arns)
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value
  type          = "STANDARD"

  tags = merge(
    var.tags,
    {
      "Cluster" = var.name
    },
  )
}

resource "aws_eks_access_policy_association" "admin" {
  for_each      = toset(var.cluster_admin_role_arns)
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}

# Poweruser roles — workload admin access (AmazonEKSAdminPolicy)
resource "aws_eks_access_entry" "poweruser" {
  for_each      = toset(var.cluster_poweruser_role_arns)
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value
  type          = "STANDARD"

  tags = merge(
    var.tags,
    {
      "Cluster" = var.name
    },
  )
}

resource "aws_eks_access_policy_association" "poweruser" {
  for_each      = toset(var.cluster_poweruser_role_arns)
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.poweruser]
}

# Read-only roles — view-only cluster access (AmazonEKSViewPolicy)
resource "aws_eks_access_entry" "readonly" {
  for_each      = toset(var.cluster_readonly_role_arns)
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value
  type          = "STANDARD"

  tags = merge(
    var.tags,
    {
      "Cluster" = var.name
    },
  )
}

resource "aws_eks_access_policy_association" "readonly" {
  for_each      = toset(var.cluster_readonly_role_arns)
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.readonly]
}

######## SECURITY GROUP

resource "aws_security_group" "eks" {
  name        = "${var.name}-eks"
  description = "Security group for EKS cluster and nodes"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      "Cluster" = var.name
    },
  )

  # AWS does not allow updating the description of an existing security group —
  # any change forces replacement. ignore_changes prevents this when upgrading
  # from older module versions that had a different description.
  lifecycle {
    ignore_changes = [description]
  }
}

# One ingress rule per allowed CIDR (all protocols/ports).
resource "aws_vpc_security_group_ingress_rule" "eks" {
  for_each          = toset(var.cidr_blocks_sg_master)
  security_group_id = aws_security_group.eks.id
  description       = "Ingress CIDR"
  ip_protocol       = "-1"
  cidr_ipv4         = each.value

  tags = merge(
    var.tags,
    {
      "Cluster" = var.name
    },
  )
}

# Default egress to anywhere (all protocols/ports).
resource "aws_vpc_security_group_egress_rule" "eks" {
  security_group_id = aws_security_group.eks.id
  description       = "Default egress"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(
    var.tags,
    {
      "Cluster" = var.name
    },
  )
}

######## IAM

resource "aws_iam_role" "eks_cluster" {
  name = "${var.name}-eks-cluster"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      },
    ]
  })
  tags = merge(
    var.tags,
    {
      "Cluster" = var.name
    },
  )
}

resource "aws_iam_role_policy_attachment" "AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

######## ADDONS EKS

# coredns
resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "coredns"
  depends_on   = [aws_eks_node_group.main]
  configuration_values = jsonencode({
    replicaCount = 2
    topologySpreadConstraints = [{
      maxSkew           = 1
      topologyKey       = "kubernetes.io/hostname"
      whenUnsatisfiable = "DoNotSchedule"
      labelSelector = {
        matchLabels = {
          "k8s-app" = "kube-dns"
        }
      }
    }]
  })
}

# kube-proxy
resource "aws_eks_addon" "kube-proxy" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "kube-proxy"
  depends_on   = [aws_eks_cluster.main]
}

# ebs-csi
resource "aws_eks_addon" "ebs-csi" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "aws-ebs-csi-driver"
  depends_on   = [aws_eks_cluster.main]
  configuration_values = jsonencode({
    controller = {
      replicaCount = 2
      topologySpreadConstraints = [{
        maxSkew           = 1
        topologyKey       = "kubernetes.io/hostname"
        whenUnsatisfiable = "ScheduleAnyway"
        labelSelector = {
          matchLabels = {
            "app.kubernetes.io/name" = "aws-ebs-csi-driver"
          }
        }
      }]
    }
  })
}

# vpc-cni
resource "aws_eks_addon" "vpc-cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"
  depends_on   = [aws_eks_cluster.main]
  configuration_values = jsonencode({
    env = {
      "ENABLE_PREFIX_DELEGATION" = var.enable_prefix_delegation,
      "WARM_PREFIX_TARGET"       = "1"
    }
  })
}

######## NODEGROUP

resource "aws_eks_node_group" "main" {
  for_each        = var.nodes_groups
  cluster_name    = var.name
  node_group_name = "${var.name}-${each.value.ng_name}"
  node_role_arn   = aws_iam_role.eks_node[each.key].arn
  subnet_ids      = each.value.ng_subnets

  force_update_version = true

  scaling_config {
    desired_size = each.value.ng_as_desired
    max_size     = each.value.ng_as_max
    min_size     = each.value.ng_as_min
  }

  launch_template {
    id      = aws_launch_template.eks_launch_template[each.key].id
    version = aws_launch_template.eks_launch_template[each.key].latest_version
  }

  depends_on = [
    aws_eks_cluster.main,
    aws_iam_role_policy_attachment.worker_node,
    aws_iam_role_policy_attachment.ecr_readonly,
    aws_iam_role_policy_attachment.cni,
    aws_eks_addon.vpc-cni,
  ]

  tags = merge(
    var.tags,
    {
      "Cluster" = var.name
    },
  )
}

resource "aws_launch_template" "eks_launch_template" {
  for_each               = var.nodes_groups
  instance_type          = each.value.ng_instance_type
  name                   = "${var.name}-${each.value.ng_name}-eks-launch-template"
  update_default_version = true
  key_name               = each.value.ng_key_name

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type = "gp3"
      volume_size = each.value.ng_volume_size
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 3
    instance_metadata_tags      = "enabled"
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      var.tags,
      {
        "Cluster" = var.name,
        "Name"    = "${var.name}-${each.value.ng_name}-eks-node"
      },
    )
  }
}

######## NODE IAM (one IAM role per node group)

resource "aws_iam_role" "eks_node" {
  for_each = var.nodes_groups
  name     = "${var.name}-${each.value.ng_name}-eks-node"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
  tags = merge(
    var.tags,
    {
      "Cluster" = var.name
    },
  )
}

# Mandatory custom policy per node group (var.nodes_groups[*].ng_iam_policy).
# It is required: if a node group needs no extra permissions, pass an empty
# policy. The for_each key is the node group key (a static string), so the
# policy ARN may be a computed value without a plan-time error.
resource "aws_iam_role_policy_attachment" "node_custom" {
  for_each   = var.nodes_groups
  role       = aws_iam_role.eks_node[each.key].name
  policy_arn = each.value.ng_iam_policy
}

# Custom managed policies, created once and attached to every node group role.
resource "aws_iam_policy" "kubernetes_cluster_autoscaler" {
  name   = "${var.name}-kubernetes-cluster-autoscaler"
  policy = file("${path.module}/iam_data/iam_kubernetes_cluster_autoscaler.json")
}

resource "aws_iam_policy" "AWSLoadBalancerControllerIAMPolicy" {
  name   = "${var.name}-AWSLoadBalancerControllerIAMPolicy"
  policy = file("${path.module}/iam_data/AWSLoadBalancerControllerIAMPolicy.json")
}

# Mandatory AWS-managed policies every node group role needs to work.
# Each attachment iterates over the per-node-group roles (aws_iam_role.eks_node).
resource "aws_iam_role_policy_attachment" "worker_node" {
  for_each   = aws_iam_role.eks_node
  role       = each.value.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "ecr_readonly" {
  for_each   = aws_iam_role.eks_node
  role       = each.value.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "cni" {
  for_each   = aws_iam_role.eks_node
  role       = each.value.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "autoscaling" {
  for_each   = aws_iam_role.eks_node
  role       = each.value.name
  policy_arn = "arn:aws:iam::aws:policy/AutoScalingFullAccess"
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  for_each   = aws_iam_role.eks_node
  role       = each.value.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# SSM Session Manager access (agent is preinstalled on the EKS-optimized AMI).
resource "aws_iam_role_policy_attachment" "ssm" {
  for_each   = aws_iam_role.eks_node
  role       = each.value.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  for_each   = aws_iam_role.eks_node
  role       = each.value.name
  policy_arn = aws_iam_policy.kubernetes_cluster_autoscaler.arn
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  for_each   = aws_iam_role.eks_node
  role       = each.value.name
  policy_arn = aws_iam_policy.AWSLoadBalancerControllerIAMPolicy.arn
}



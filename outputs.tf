######## CLUSTER

output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.main.name
}

output "cluster_arn" {
  description = "EKS cluster ARN."
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "Endpoint of the Kubernetes API server."
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  description = "Kubernetes version running on the cluster."
  value       = aws_eks_cluster.main.version
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data for the cluster."
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL of the cluster (for IRSA)."
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "cluster_security_group_id" {
  description = "ID of the security group created for the cluster and nodes."
  value       = aws_security_group.eks.id
}

######## IAM

output "cluster_role_arn" {
  description = "ARN of the IAM role assumed by the EKS control plane."
  value       = aws_iam_role.eks_cluster.arn
}

output "node_role_arns" {
  description = "Map of node group key => worker node IAM role ARN."
  value       = { for k, r in aws_iam_role.eks_node : k => r.arn }
}

output "node_role_names" {
  description = "Map of node group key => worker node IAM role name (to attach extra policies)."
  value       = { for k, r in aws_iam_role.eks_node : k => r.name }
}

######## NODE GROUPS

output "node_groups" {
  description = "Map of created node groups keyed by their configuration key."
  value = {
    for k, ng in aws_eks_node_group.main : k => {
      node_group_name = ng.node_group_name
      arn             = ng.arn
      status          = ng.status
    }
  }
}

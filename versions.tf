terraform {
  required_version = ">= 1.3.7"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # aws_eks_cluster.deletion_protection requires provider >= 6.9.0.
      # https://github.com/hashicorp/terraform-provider-aws/blob/main/CHANGELOG.md
      version = ">= 6.9.0"
    }
  }
}

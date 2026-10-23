# =============================================================================
# Legacy Compute Decommissioned
# =============================================================================
# The single-node EC2 instance, Elastic IP, and K3s bootstrap scripts previously
# defined in this file have been decommissioned and migrated to enterprise-grade
# Amazon EKS architecture.
#
# Active Compute Resources:
# - Amazon EKS Cluster: terraform/eks.tf (aws_eks_cluster.main)
# - EKS Managed Node Group: terraform/eks.tf (aws_eks_node_group.main)
# - AWS EBS CSI Driver Add-On: terraform/eks.tf (aws_eks_addon.ebs_csi)
# =============================================================================

output "region" {
  description = "AWS region the infrastructure lives in."
  value       = var.region
}

output "elastic_ip" {
  description = "Static public IP assigned to the K3s node."
  value       = aws_eip.node.public_ip
}

output "store_url" {
  description = "Application URL."
  value       = "http://${aws_eip.node.public_ip}/"
}

output "cloudflare_dns_record" {
  description = "DNS record configuration for Cloudflare."
  value = {
    type    = "A"
    name    = var.domain_name != "" ? var.domain_name : "duckstore.<your-domain>"
    content = aws_eip.node.public_ip
    proxied = true
    ttl     = "Auto"
  }
}

output "instance_id" {
  description = "EC2 instance ID of the K3s node."
  value       = aws_instance.node.id
}

output "instance_private_ip" {
  description = "Private IP inside the VPC."
  value       = aws_instance.node.private_ip
}

output "ami_id" {
  description = "AMI ID used for the node."
  value       = data.aws_ami.ubuntu.id
}

output "ssm_session_command" {
  description = "Open an SSM shell session on the node."
  value       = "aws ssm start-session --target ${aws_instance.node.id} --region ${var.region}"
}

output "ssh_command" {
  description = "SSH command if key_pair_name and ssh_allowed_cidrs are configured."
  value       = var.key_pair_name != "" ? "ssh -i ~/.ssh/${var.key_pair_name}.pem ubuntu@${aws_eip.node.public_ip}" : "SSH not configured"
}

output "watch_bootstrap" {
  description = "Follow the bootstrap log via SSM."
  value       = "aws ssm start-session --target ${aws_instance.node.id} --region ${var.region} --document-name AWS-StartInteractiveCommand --parameters command='sudo tail -f /var/log/duckstore-bootstrap.log'"
}

output "fetch_kubeconfig" {
  description = "Commands to retrieve the cluster kubeconfig (requires sudo on the host for 0600 permissions)."
  value = join(" && ", [
    "ssh ubuntu@${aws_eip.node.public_ip} 'sudo cat /etc/rancher/k3s/k3s.yaml' > ~/.kube/duckstore.yaml",
    "sed -i 's/127.0.0.1/${aws_eip.node.public_ip}/' ~/.kube/duckstore.yaml",
    "chmod 600 ~/.kube/duckstore.yaml",
    "KUBECONFIG=~/.kube/duckstore.yaml kubectl get pods -A",
  ])
}

output "fetch_kubeconfig_ssm" {
  description = "Retrieve the cluster kubeconfig securely over AWS SSM without direct SSH access."
  value = join(" && ", [
    "CMD_ID=$(aws ssm send-command --instance-ids ${aws_instance.node.id} --region ${var.region} --document-name AWS-RunShellScript --parameters 'commands=[\"sudo cat /etc/rancher/k3s/k3s.yaml\"]' --query 'Command.CommandId' --output text)",
    "aws ssm wait command-executed --command-id $CMD_ID --instance-id ${aws_instance.node.id} --region ${var.region}",
    "aws ssm get-command-invocation --command-id $CMD_ID --instance-id ${aws_instance.node.id} --region ${var.region} --query 'StandardOutputContent' --output text > ~/.kube/duckstore.yaml",
    "sed -i 's/127.0.0.1/${aws_eip.node.public_ip}/' ~/.kube/duckstore.yaml",
    "chmod 600 ~/.kube/duckstore.yaml",
    "KUBECONFIG=~/.kube/duckstore.yaml kubectl get pods -A",
  ])
}

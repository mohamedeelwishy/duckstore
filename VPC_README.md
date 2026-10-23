# Amazon VPC Architecture & Network Interconnection Guide

## 1. Overview & Core Specifications

This document outlines the architectural specifications, subnet topology, and external connectivity design for the Amazon Virtual Private Cloud (VPC) hosting the **DuckStore** production EKS microservices infrastructure.

### VPC Specifications
| Attribute | Value | Description |
| :--- | :--- | :--- |
| **VPC Name** | `duckstore-prod-vpc` | Managed via Terraform (`local.name-vpc`) |
| **VPC ID** | `vpc-0a1b2c3d4e5f60789` *(Dynamic Terraform reference: `aws_vpc.main.id`)* | Primary VPC Identifier |
| **VPC ARN** | `arn:aws:ec2:eu-west-1:123456789012:vpc/vpc-0a1b2c3d4e5f60789` *(Dynamic: `aws_vpc.main.arn`)* | Amazon Resource Name |
| **Primary IPv4 CIDR** | `10.0.0.0/16` (65,536 Total IP Addresses) | RFC 1918 Private Address Space |
| **Region & AZs** | `eu-west-1` (`eu-west-1a`, `eu-west-1b`) | Multi-Availability Zone redundancy |
| **DNS Attributes** | `enable_dns_support = true`, `enable_dns_hostnames = true` | Required for EKS cluster internal service discovery |

---

## 2. Subnet Allocation & CIDR Breakdown

The CIDR block `10.0.0.0/16` is partitioned across two (2) Availability Zones to ensure high availability and accommodate both internet-facing Application Load Balancers (ALB) and private EKS worker nodes.

```
                                  VPC: 10.0.0.0/16
                                         │
        ┌────────────────────────────────┴────────────────────────────────┐
        ▼                                                                 ▼
Availability Zone: eu-west-1a                             Availability Zone: eu-west-1b
┌───────────────────────────────┐                         ┌───────────────────────────────┐
│ Public Subnet 1 (`10.0.1.0/24`)│                         │ Public Subnet 2 (`10.0.2.0/24`)│
│ - Internet Gateway Routing    │                         │ - Internet Gateway Routing    │
│ - AWS ALB (Internet-Facing)   │                         │ - AWS ALB (Internet-Facing)   │
│ - NAT Gateway                 │                         │                               │
│ Tag: kubernetes.io/role/elb=1 │                         │ Tag: kubernetes.io/role/elb=1 │
├───────────────────────────────┤                         ├───────────────────────────────┤
│ Private Subnet 1(`10.0.10.0/24`)                        │ Private Subnet 2(`10.0.20.0/24`)
│ - NAT Gateway Egress Routing  │                         │ - NAT Gateway Egress Routing  │
│ - EKS Managed Nodes (t3.medium│                         │ - EKS Managed Nodes (t3.medium│
│ - Pod IP Targets (AWS VPC CNI)│                         │ - Pod IP Targets (AWS VPC CNI)│
│ Tag: role/internal-elb=1      │                         │ Tag: role/internal-elb=1      │
└───────────────────────────────┘                         └───────────────────────────────┘
```

### Detailed Subnet Breakdown Table

| Subnet Identifier | CIDR Block | Usable IPs | Availability Zone | Tier | Purpose & EKS Tagging |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`public-1a`** | `10.0.1.0/24` | 251 | `eu-west-1a` | Public | Internet Gateway target, AWS ALB Ingress endpoint, NAT Gateway.<br>`kubernetes.io/role/elb = 1`<br>`kubernetes.io/cluster/duckstore-prod-eks = shared` |
| **`public-1b`** | `10.0.2.0/24` | 251 | `eu-west-1b` | Public | Secondary ALB endpoint for AZ resilience.<br>`kubernetes.io/role/elb = 1`<br>`kubernetes.io/cluster/duckstore-prod-eks = shared` |
| **`private-1a`** | `10.0.10.0/24` | 251 | `eu-west-1a` | Private | EKS Managed Node Group, Pod IP allocation via AWS VPC CNI, EBS PV attachments.<br>`kubernetes.io/role/internal-elb = 1`<br>`kubernetes.io/cluster/duckstore-prod-eks = shared` |
| **`private-1b`** | `10.0.20.0/24` | 251 | `eu-west-1b` | Private | Secondary EKS Managed Node Group pool, distributed stateful workloads.<br>`kubernetes.io/role/internal-elb = 1`<br>`kubernetes.io/cluster/duckstore-prod-eks = shared` |
| *Reserved (Future)* | `10.0.30.0/20` | ~4,090 | Multi-AZ | Private | Reserved for dedicated DB tier (Amazon RDS / Aurora PostgreSQL) or additional EKS node pools. |

> [!NOTE]
> AWS reserves 5 IP addresses per subnet (`.0` network address, `.1` VPC router, `.2` Amazon DNS server, `.3` future use, and `.255` broadcast).

---

## 3. Routing & Internet Gateway Architecture

1. **Public Route Table (`duckstore-prod-public-rt`)**:
   - Destination `10.0.0.0/16` -> Target `local`
   - Destination `0.0.0.0/0` -> Target `igw-xxxxxxxx` (`aws_internet_gateway.main`)
   - Associated with `public-1a` and `public-1b`.

2. **Private Route Table (`duckstore-prod-private-rt`)**:
   - Destination `10.0.0.0/16` -> Target `local`
   - Destination `0.0.0.0/0` -> Target `nat-xxxxxxxx` (`aws_nat_gateway.main`)
   - Associated with `private-1a` and `private-1b`.
   - Protects EKS worker nodes and database storage from direct internet exposure while enabling outbound egress for OS package updates, ECR image pulls, and external API integrations.

---

## 4. Theoretical Connection Guide: Interconnecting with External Networks

When connecting the DuckStore VPC to an external network (e.g., a corporate data center, an administrative/shared-services VPC, or a partner cloud environment), two primary AWS interconnection patterns are recommended: **VPC Peering** and **AWS Transit Gateway (TGW)**.

### 4.1. Network Interconnection Prerequisites & Conflict Avoidance

#### Mandatory Rule: Non-Overlapping CIDRs
- **Strict IP Planning**: The interconnecting network MUST NOT overlap with `10.0.0.0/16`.
- If an on-premises network or remote VPC uses `10.0.0.0/16` (or any sub-range like `10.0.1.0/24`), routing collisions occur and traffic cannot be deterministically delivered.
- **Remediation for Overlapping IP Spaces**: If the external network cannot change its IP space, employ **AWS PrivateLink** (for exposing specific services) or deploy a dual-sided **NAT Gateway / Carrier-Grade NAT** pattern before peering.

---

### 4.2. Option A: AWS VPC Peering (Point-to-Point)

Best suited for a direct 1-to-1 connection with another VPC (e.g., a Shared Services or Monitoring VPC in `10.100.0.0/16`).

```
┌─────────────────────────────────┐                 ┌─────────────────────────────────┐
│     DuckStore Production VPC    │                 │      Shared Services VPC        │
│          (10.0.0.0/16)          │                 │         (10.100.0.0/16)         │
│                                 │   VPC Peering   │                                 │
│  Private Subnet: 10.0.10.0/24   │◄───────────────►│  Private Subnet: 10.100.1.0/24  │
│  Route: 10.100.0.0/16 -> pcx-xx │    (pcx-xxxx)   │  Route: 10.0.0.0/16 -> pcx-xx   │
└─────────────────────────────────┘                 └─────────────────────────────────┘
```

#### Step-by-Step Implementation:
1. **Create Peering Connection (`aws_vpc_peering_connection`)**:
   - Requester VPC: `aws_vpc.main.id` (`10.0.0.0/16`)
   - Accepter VPC: Peer VPC ID (`10.100.0.0/16`) and AWS Account ID.
   - Accept the peering connection request in the peer account.

2. **Update Route Tables**:
   - In DuckStore VPC Private Route Table:
     - Add route: Destination `10.100.0.0/16` -> Target `pcx-xxxxxxxx`.
   - In Remote VPC Route Table:
     - Add route: Destination `10.0.0.0/16` -> Target `pcx-xxxxxxxx`.

3. **Update Security Group Ingress Rules**:
   - In DuckStore EKS Worker Nodes / Workloads:
     ```hcl
     resource "aws_vpc_security_group_ingress_rule" "allow_peered_monitoring" {
       security_group_id = aws_security_group.eks_nodes.id
       description       = "Allow Prometheus metrics scraping from Shared Services VPC"
       cidr_ipv4         = "10.100.0.0/16"
       ip_protocol       = "tcp"
       from_port         = 9090
       to_port           = 9090
     }
     ```

4. **DNS Resolution**:
   - Enable `allow_remote_vpc_dns_resolution` in the peering connection options so private Route 53 zones resolve across VPC boundaries.

---

### 4.3. Option B: AWS Transit Gateway (Hub-and-Spoke Enterprise Architecture)

Best suited for enterprise multi-VPC, hybrid cloud (AWS Direct Connect / Site-to-Site VPN), and centralized egress architectures.

```
       ┌────────────────────────┐
       │   Corporate On-Prem /  │
       │    Data Center Network │
       │     (192.168.0.0/16)   │
       └───────────┬────────────┘
                   │ (Direct Connect / IPsec VPN)
                   ▼
       ┌────────────────────────┐
       │  AWS Transit Gateway   │◄─────────────────────────────┐
       │       (TGW Hub)        │                              │
       └───────────┬────────────┘                              │
                   │                                           │
         ┌─────────┴─────────┐                       ┌─────────┴─────────┐
         ▼                   ▼                       ▼                   ▼
┌─────────────────┐ ┌─────────────────┐     ┌─────────────────┐ ┌─────────────────┐
│  DuckStore Prod │ │ Shared Services │     │   Security /    │ │ Egress Gateway  │
│   (10.0.0.0/16) │ │ (10.100.0.0/16) │     │ Inspection VPC  │ │ Central VPC     │
└─────────────────┘ └─────────────────┘     └─────────────────┘ └─────────────────┘
```

#### Step-by-Step Implementation:
1. **Transit Gateway Attachment (`aws_ec2_transit_gateway_vpc_attachment`)**:
   - Create a VPC attachment targeting DuckStore VPC.
   - Attach the **Private Subnets** (`10.0.10.0/24` and `10.0.20.0/24`) across both AZs (`eu-west-1a`, `eu-west-1b`). EKS requires ENIs in private subnets for proper asymmetric routing prevention.

2. **Route Table Configuration**:
   - **DuckStore Private Route Table**:
     - Route to all internal corporate networks (`10.0.0.0/8` or specific CIDRs `192.168.0.0/16`, `10.100.0.0/16`) -> Target `tgw-xxxxxxxx`.
   - **Transit Gateway Route Table**:
     - Associate DuckStore attachment with the Spoke TGW Route Table.
     - Propagate DuckStore CIDR (`10.0.0.0/16`) to the TGW route table so other spokes and on-premises routers learn the path.

3. **Security Groups & Network Segmentation**:
   - Treat the TGW attachments as transit interfaces.
   - Apply strict ingress/egress rules on EKS Node and Pod security groups allowing traffic strictly from designated external subnets on permitted application ports.

---

## 5. Security Summary & Best Practices

1. **Zero Public Nodes**: All EKS worker nodes and database persistent disks are strictly isolated in Private Subnets.
2. **Controlled Ingress**: Inbound traffic enters exclusively through the AWS ALB placed in the Public Subnets.
3. **IMDSv2 Enforced**: Token hop limit and required token enforcement protect against SSRF credential leakage.
4. **Least Privilege Routing**: Route tables expose only `0.0.0.0/0` via NAT Gateway for egress, with local peering/TGW routes defined strictly for authorized destination CIDRs.


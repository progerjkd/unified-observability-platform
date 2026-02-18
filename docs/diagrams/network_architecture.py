"""
Network Architecture Diagram - Unified Observability Platform
Shows VPC layout, subnets across 3 AZs, security groups, and routing
"""

from diagrams import Diagram, Cluster, Edge
from diagrams.aws.network import VPC, PrivateSubnet, PublicSubnet, NATGateway, InternetGateway, Route53, RouteTable, ELB
from diagrams.aws.compute import EKS, EC2, ECS
from diagrams.aws.security import IAM
from diagrams.onprem.network import Internet

graph_attr = {
    "fontsize": "14",
    "bgcolor": "white",
    "pad": "0.5",
    "ranksep": "1.0",
}

with Diagram("Network Architecture - VPC & Subnets",
             filename="network_architecture",
             outformat="png",
             show=False,
             direction="TB",
             graph_attr=graph_attr):

    internet = Internet("Internet")
    dc_onprem = EC2("Direct Connect\nOn-Premises")

    with Cluster("AWS Region (us-east-1)"):
        igw = InternetGateway("Internet Gateway")

        with Cluster("VPC (10.0.0.0/16)"):
            route53 = Route53("Private Zone\nobservability.internal")

            with Cluster("Availability Zone 1 (us-east-1a)"):
                with Cluster("Public Subnet\n10.0.1.0/24"):
                    nat_1 = NATGateway("NAT Gateway")

                with Cluster("Private Subnet\n10.0.101.0/24"):
                    eks_node_1a = EKS("EKS Nodes")
                    nlb_1a = ELB("NLB Target")

            with Cluster("Availability Zone 2 (us-east-1b)"):
                with Cluster("Public Subnet\n10.0.2.0/24"):
                    nat_2 = NATGateway("NAT Gateway")

                with Cluster("Private Subnet\n10.0.102.0/24"):
                    eks_node_1b = EKS("EKS Nodes")
                    nlb_1b = ELB("NLB Target")

            with Cluster("Availability Zone 3 (us-east-1c)"):
                with Cluster("Public Subnet\n10.0.3.0/24"):
                    nat_3 = NATGateway("NAT Gateway")

                with Cluster("Private Subnet\n10.0.103.0/24"):
                    eks_node_1c = EKS("EKS Nodes")
                    nlb_1c = ELB("NLB Target")

            with Cluster("Network Load Balancer"):
                nlb = ELB("otel-gateway\nInternal NLB\nCross-Zone LB")

            with Cluster("Security Groups"):
                sg_gateway = IAM("otel-gateway-sg\nIngress: :4317, :4318\nfrom VPC + On-Prem")
                sg_eks = IAM("eks-cluster-sg\nIngress: K8s API")

    # Internet Gateway to Public Subnets
    internet >> igw
    igw >> Edge(label="outbound") >> nat_1
    igw >> Edge(label="outbound") >> nat_2
    igw >> Edge(label="outbound") >> nat_3

    # NAT Gateways to Private Subnets
    nat_1 >> Edge(label="internet access", style="dashed") >> eks_node_1a
    nat_2 >> Edge(label="internet access", style="dashed") >> eks_node_1b
    nat_3 >> Edge(label="internet access", style="dashed") >> eks_node_1c

    # Direct Connect to NLB
    dc_onprem >> Edge(label="OTLP :4317", color="blue") >> nlb

    # NLB to targets across AZs
    nlb >> nlb_1a
    nlb >> nlb_1b
    nlb >> nlb_1c

    # Route53 to NLB
    route53 >> Edge(label="gateway.observability.internal\nAlias Record") >> nlb

    # Security Groups
    sg_gateway - Edge(label="attached to", style="dotted") - nlb
    sg_eks - Edge(label="attached to", style="dotted") - eks_node_1a

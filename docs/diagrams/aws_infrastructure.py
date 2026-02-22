"""
AWS Infrastructure Diagram - Unified Observability Platform
Shows VPC, EKS, S3, IAM, NLB, Route53 resources
"""

from diagrams import Diagram, Cluster, Edge
from diagrams.aws.network import VPC, PrivateSubnet, PublicSubnet, NATGateway, Route53, ELB
from diagrams.aws.compute import EKS, EC2, ECS
from diagrams.aws.storage import S3
from diagrams.aws.security import IAM, KMS
from diagrams.onprem.network import Internet

graph_attr = {
    "fontsize": "14",
    "bgcolor": "white",
    "pad": "0.5",
}

with Diagram("AWS Infrastructure - Observability Platform",
             filename="aws_infrastructure",
             outformat="png",
             show=False,
             direction="TB",
             graph_attr=graph_attr):

    internet = Internet("Internet")
    onprem = EC2("On-Premises\n(Direct Connect)")

    with Cluster("AWS Account"):
        kms = KMS("KMS Key\nEncryption")

        with Cluster("VPC (10.0.0.0/16)"):
            route53_zone = Route53("observability.internal\n(Private Zone)")

            with Cluster("Public Subnets"):
                nat_gw = NATGateway("NAT Gateways\n(3 AZs)")

            with Cluster("Private Subnets (3 AZs)"):
                nlb = ELB("Internal NLB\notel-gateway")

                with Cluster("EKS Cluster (obs-lgtm)"):
                    with Cluster("Node Groups"):
                        general_ng = EKS("general\n2x c6i.2xlarge")
                        write_ng = EKS("write-path\n3x c6i.2xlarge")
                        mimir_ng = EKS("mimir-ingesters\n3x r6i.2xlarge")
                        loki_ng = EKS("loki-ingesters\n3x r6i.xlarge")
                        tempo_ng = EKS("tempo-ingesters\n3x r6i.xlarge")

                    with Cluster("LGTM Backend Pods"):
                        gateway_pods = ECS("OTel Gateway\n3 replicas + HPA")
                        mimir = ECS("Mimir\n(Metrics)")
                        loki = ECS("Loki\n(Logs)")
                        tempo = ECS("Tempo\n(Traces)")
                        grafana = ECS("Grafana\n(Visualization)")

        with Cluster("S3 Storage"):
            s3_mimir = S3("mimir")
            s3_loki = S3("loki")
            s3_tempo = S3("tempo")

        with Cluster("IAM / IRSA"):
            irsa_mimir = IAM("IRSA Role\nMimir")
            irsa_loki = IAM("IRSA Role\nLoki")
            irsa_tempo = IAM("IRSA Role\nTempo")

    # External connections
    internet >> Edge(label="NAT") >> nat_gw
    onprem >> Edge(label="Direct Connect\nOTLP :4317") >> nlb

    # Route53 DNS
    route53_zone >> Edge(label="gateway.observability.internal") >> nlb

    # NLB to Gateway
    nlb >> Edge(label="TCP :4317") >> gateway_pods

    # Gateway to backends
    gateway_pods >> Edge(label="OTLP") >> mimir
    gateway_pods >> Edge(label="OTLP") >> loki
    gateway_pods >> Edge(label="OTLP") >> tempo

    # Backend to S3 via IRSA
    mimir >> Edge(label="IRSA") >> irsa_mimir >> Edge(label="encrypted") >> s3_mimir
    loki >> Edge(label="IRSA") >> irsa_loki >> Edge(label="encrypted") >> s3_loki
    tempo >> Edge(label="IRSA") >> irsa_tempo >> Edge(label="encrypted") >> s3_tempo

    # KMS encryption
    kms >> Edge(label="encrypts", style="dotted") >> s3_mimir
    kms >> Edge(label="encrypts", style="dotted") >> s3_loki
    kms >> Edge(label="encrypts", style="dotted") >> s3_tempo

    # Grafana queries
    grafana >> Edge(label="PromQL", color="orange", style="dashed") >> mimir
    grafana >> Edge(label="LogQL", color="blue", style="dashed") >> loki
    grafana >> Edge(label="TraceQL", color="green", style="dashed") >> tempo

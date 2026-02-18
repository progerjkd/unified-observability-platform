"""
Data Flow Diagram - Unified Observability Platform
Shows telemetry flow from ~500 compute instances through gateway to LGTM backend
"""

from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import EKS, ECS, EC2
from diagrams.onprem.compute import Server
from diagrams.onprem.monitoring import Grafana
from diagrams.custom import Custom
from diagrams.programming.framework import React

graph_attr = {
    "fontsize": "14",
    "bgcolor": "white",
    "pad": "0.5",
}

with Diagram("Telemetry Data Flow - 500 Compute Instances",
             filename="data_flow",
             outformat="png",
             show=False,
             direction="LR",
             graph_attr=graph_attr):

    with Cluster("Collection Layer (~500 Instances)"):
        with Cluster("AWS"):
            eks_agents = EKS("EKS Linux\nDaemonSet\n(Operator)")
            fargate_agents = ECS("ECS Fargate\nSidecar")
            ecs_linux = ECS("ECS EC2 Linux\nDaemon Task")
            ecs_windows = ECS("ECS EC2 Win\nMSI Service")
            ec2_linux = EC2("EC2 Linux\nsystemd")
            ec2_windows = EC2("EC2 Windows\nMSI Service")

        with Cluster("On-Premises"):
            onprem_linux = Server("Linux\nsystemd")
            onprem_windows = Server("Windows\nMSI Service")

    with Cluster("Gateway Layer"):
        with Cluster("AWS EKS"):
            gateway = ECS("OTel Gateway\n3 replicas + HPA")
            gateway_features = React("• Tail Sampling\n• Health Filter\n• Attribute Transform")

    with Cluster("Backend Layer (LGTM)"):
        with Cluster("Storage & Query"):
            mimir = ECS("Mimir\nMetrics\nPromQL")
            loki = ECS("Loki\nLogs\nLogQL")
            tempo = ECS("Tempo\nTraces\nTraceQL")

        visualization = Grafana("Grafana\nDashboards\nAlerts\nExplore")

    # Agent to Gateway (OTLP gRPC)
    otlp_edge = Edge(label="OTLP gRPC\n:4317", color="darkblue")
    eks_agents >> otlp_edge >> gateway
    fargate_agents >> otlp_edge >> gateway
    ecs_linux >> otlp_edge >> gateway
    ecs_windows >> otlp_edge >> gateway
    ec2_linux >> otlp_edge >> gateway
    ec2_windows >> otlp_edge >> gateway
    onprem_linux >> Edge(label="OTLP gRPC\nDirect Connect", color="darkblue") >> gateway
    onprem_windows >> Edge(label="OTLP gRPC\nDirect Connect", color="darkblue") >> gateway

    # Gateway processing
    gateway - Edge(style="invis") - gateway_features

    # Gateway to Backends (OTLP HTTP)
    gateway >> Edge(label="Metrics\nOTLP HTTP", color="orange") >> mimir
    gateway >> Edge(label="Logs\nOTLP HTTP", color="blue") >> loki
    gateway >> Edge(label="Traces\nOTLP HTTP", color="green") >> tempo

    # Tempo generates metrics
    tempo >> Edge(label="RED metrics\nExemplars", color="red", style="dashed") >> mimir

    # Backends to Grafana
    visualization >> Edge(label="PromQL", color="orange", style="dotted") >> mimir
    visualization >> Edge(label="LogQL", color="blue", style="dotted") >> loki
    visualization >> Edge(label="TraceQL", color="green", style="dotted") >> tempo

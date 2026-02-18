"""
EKS Cluster Diagram - Unified Observability Platform
Detailed view of EKS node groups and LGTM component placement
"""

from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import EKS
from diagrams.k8s.compute import Pod, DaemonSet, Deployment, StatefulSet
from diagrams.k8s.network import Service, Ingress
from diagrams.k8s.controlplane import APIServer
from diagrams.aws.storage import S3
from diagrams.aws.network import ELB

graph_attr = {
    "fontsize": "14",
    "bgcolor": "white",
    "pad": "0.5",
}

with Diagram("EKS Cluster Architecture - obs-lgtm",
             filename="eks_cluster",
             outformat="png",
             show=False,
             direction="TB",
             graph_attr=graph_attr):

    external_nlb = ELB("Internal NLB\ngateway.observability.internal")

    with Cluster("EKS Cluster (obs-lgtm)"):
        api_server = APIServer("EKS Control Plane")

        with Cluster("general Node Group (2x c6i.2xlarge)"):
            otel_operator = Deployment("OTel Operator")
            otel_gateway_deploy = Deployment("OTel Gateway\n3 replicas")
            grafana_pod = Pod("Grafana")
            prometheus_pod = Pod("Prometheus\n(optional)")

        with Cluster("write-path Node Group (3x c6i.2xlarge)"):
            mimir_distributor = StatefulSet("Mimir\nDistributor")
            mimir_ingester = StatefulSet("Mimir\nIngester")
            loki_distributor = StatefulSet("Loki\nDistributor")
            tempo_distributor = StatefulSet("Tempo\nDistributor")

        with Cluster("mimir-ingesters Node Group (3x r6i.2xlarge)"):
            mimir_ingester_1 = Pod("Mimir Ingester-1")
            mimir_ingester_2 = Pod("Mimir Ingester-2")
            mimir_ingester_3 = Pod("Mimir Ingester-3")
            mimir_store_gateway = Pod("Store Gateway")

        with Cluster("loki-ingesters Node Group (3x r6i.xlarge)"):
            loki_ingester_1 = Pod("Loki Ingester-1")
            loki_ingester_2 = Pod("Loki Ingester-2")
            loki_ingester_3 = Pod("Loki Ingester-3")
            loki_querier = Pod("Querier")

        with Cluster("tempo-ingesters Node Group (3x r6i.xlarge)"):
            tempo_ingester_1 = Pod("Tempo Ingester-1")
            tempo_ingester_2 = Pod("Tempo Ingester-2")
            tempo_ingester_3 = Pod("Tempo Ingester-3")
            tempo_compactor = Pod("Compactor")
            tempo_metrics_gen = Pod("Metrics Generator")

        with Cluster("All Nodes"):
            otel_daemonset = DaemonSet("OTel Collector\nDaemonSet")

    with Cluster("S3 Storage"):
        s3_mimir = S3("obs-mimir\nChunks, Blocks, Index")
        s3_loki = S3("obs-loki\nChunks, Index")
        s3_tempo = S3("obs-tempo\nBlocks, WAL")

    # External to cluster
    external_nlb >> Edge(label="TCP :4317") >> otel_gateway_deploy

    # OTel Operator manages DaemonSet
    otel_operator >> Edge(label="manages", style="dashed") >> otel_daemonset

    # DaemonSet to Gateway
    otel_daemonset >> Edge(label="pod telemetry\nOTLP") >> otel_gateway_deploy

    # Gateway to Distributors
    otel_gateway_deploy >> Edge(label="metrics", color="orange") >> mimir_distributor
    otel_gateway_deploy >> Edge(label="logs", color="blue") >> loki_distributor
    otel_gateway_deploy >> Edge(label="traces", color="green") >> tempo_distributor

    # Distributors to Ingesters (Mimir)
    mimir_distributor >> mimir_ingester_1
    mimir_distributor >> mimir_ingester_2
    mimir_distributor >> mimir_ingester_3

    # Distributors to Ingesters (Loki)
    loki_distributor >> loki_ingester_1
    loki_distributor >> loki_ingester_2
    loki_distributor >> loki_ingester_3

    # Distributors to Ingesters (Tempo)
    tempo_distributor >> tempo_ingester_1
    tempo_distributor >> tempo_ingester_2
    tempo_distributor >> tempo_ingester_3

    # Ingesters to S3
    mimir_ingester_3 >> Edge(label="flush", color="orange") >> s3_mimir
    loki_ingester_3 >> Edge(label="flush", color="blue") >> s3_loki
    tempo_ingester_3 >> Edge(label="flush", color="green") >> s3_tempo

    # Store Gateway reads from S3
    mimir_store_gateway >> Edge(label="query", style="dotted") >> s3_mimir
    loki_querier >> Edge(label="query", style="dotted") >> s3_loki

    # Tempo metrics generator produces metrics
    tempo_metrics_gen >> Edge(label="RED metrics\nexemplars", color="red", style="dashed") >> mimir_distributor

    # Grafana queries
    grafana_pod >> Edge(label="PromQL") >> mimir_store_gateway
    grafana_pod >> Edge(label="LogQL") >> loki_querier
    grafana_pod >> Edge(label="TraceQL") >> tempo_compactor

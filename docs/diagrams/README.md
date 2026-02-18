# Architecture Diagrams

Professional AWS architecture diagrams for the Unified Observability Platform, generated using the [diagrams](https://diagrams.mingrammer.com/) Python library with official AWS icons.

## Generated Diagrams

1. **`aws_infrastructure.png`** - Complete AWS infrastructure overview
   - VPC, subnets, NLB, Route53
   - EKS cluster with node groups
   - S3 buckets for LGTM storage
   - IAM IRSA roles
   - KMS encryption

2. **`data_flow.png`** - Telemetry data flow from ~500 compute instances
   - Collection layer: EKS, ECS, EC2, on-premises agents
   - Gateway layer: OTel Gateway with tail sampling
   - Backend layer: Mimir (metrics), Loki (logs), Tempo (traces)
   - Grafana visualization

3. **`eks_cluster.png`** - Detailed EKS cluster architecture
   - Node groups: general, write-path, mimir-ingesters, loki-ingesters, tempo-ingesters
   - LGTM component placement (distributors, ingesters, queriers)
   - OTel Operator and DaemonSet
   - S3 storage connections

4. **`network_architecture.png`** - VPC network layout
   - 3 Availability Zones (us-east-1a/b/c)
   - Public subnets with NAT Gateways
   - Private subnets with EKS nodes
   - Internal NLB with cross-zone load balancing
   - Security groups and Route53 private zone

## Prerequisites

### macOS

```bash
# Install Graphviz (required by diagrams library)
brew install graphviz

# Install Python dependencies
pip install -r requirements.txt
```

### Linux (Ubuntu/Debian)

```bash
# Install Graphviz
sudo apt-get update
sudo apt-get install graphviz

# Install Python dependencies
pip install -r requirements.txt
```

### Linux (RHEL/CentOS/Amazon Linux)

```bash
# Install Graphviz
sudo yum install graphviz

# Install Python dependencies
pip install -r requirements.txt
```

## Generating Diagrams

### Generate All Diagrams

```bash
# From the docs/diagrams/ directory
python3 generate_all.py
```

### Generate Individual Diagram

```bash
# AWS infrastructure
python3 aws_infrastructure.py

# Data flow
python3 data_flow.py

# EKS cluster
python3 eks_cluster.py

# Network architecture
python3 network_architecture.py
```

## Output

All diagrams are generated as PNG files in this directory:
- `aws_infrastructure.png`
- `data_flow.png`
- `eks_cluster.png`
- `network_architecture.png`

## Customization

Each `.py` file contains the diagram-as-code definition. You can customize:

- **Colors**: Modify `Edge(color="...")` parameters
- **Layout**: Change `direction="TB"` (top-to-bottom) or `"LR"` (left-to-right)
- **Labels**: Update node labels and edge descriptions
- **Clusters**: Add/remove grouping boxes
- **Icons**: Use different AWS icons from the `diagrams.aws.*` modules

See the [diagrams documentation](https://diagrams.mingrammer.com/docs/getting-started/installation) for more details.

## Updating Infrastructure

When the infrastructure changes:

1. Edit the relevant `.py` file(s)
2. Regenerate diagrams: `python3 generate_all.py`
3. Commit both the `.py` source and `.png` outputs to version control

## Troubleshooting

### Graphviz not found

**Error**: `graphviz executables not found`

**Solution**: Install Graphviz using your package manager (see Prerequisites above)

### Permission denied

**Error**: `Permission denied: generate_all.py`

**Solution**: Make the script executable:
```bash
chmod +x generate_all.py
```

### Import errors

**Error**: `ModuleNotFoundError: No module named 'diagrams'`

**Solution**: Install Python dependencies:
```bash
pip install -r requirements.txt
```

## CI/CD Integration

To regenerate diagrams automatically in CI pipelines:

```yaml
# GitHub Actions example
- name: Install Graphviz
  run: sudo apt-get install -y graphviz

- name: Install Python dependencies
  run: pip install -r docs/diagrams/requirements.txt

- name: Generate diagrams
  run: python3 docs/diagrams/generate_all.py

- name: Commit diagrams
  run: |
    git config user.name "GitHub Actions"
    git config user.email "actions@github.com"
    git add docs/diagrams/*.png
    git commit -m "chore: regenerate architecture diagrams" || true
    git push
```

## Resources

- [Diagrams Library](https://diagrams.mingrammer.com/)
- [AWS Icons Reference](https://diagrams.mingrammer.com/docs/nodes/aws)
- [Graphviz](https://graphviz.org/)

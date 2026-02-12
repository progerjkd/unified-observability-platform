# Overview

Design an unified observability platform to be retrofitted across a heterogeneous environment
spanning multiple compute platforms, operating systems, and geographic regions. Your solution
should address metrics, logs, and traces while minimizing cloud vendor lock-in.

# Environment Context

The target environment consists of the following workloads, all of which need to be enrolled in
observability:

- EKS Linux
- ECS Fargate Linux
- ECS EC2 Linux
- ECS EC2 Windows
- EC2 Linux
- EC2 Windows
- On-prem Windows
- On-prem Linux

# Assume:

- ~500 total compute instances/tasks across all platforms
- Applications are a mix of .NET (Windows), .NET Core, Java, and Node.js
- Some legacy apps cannot be modified (agent-only instrumentation)
- Networking between on-prem and cloud is established (Direct Connect)
- Budget is a consideration but not the primary constraint

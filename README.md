# Hetzner Kafka Deployment

Automated deployment of Apache Kafka in KRaft mode (without ZooKeeper) on Hetzner Cloud servers using GitHub Actions.

## Project Structure

```
deployment/
├── .github/workflows/           # GitHub Actions workflows
│   ├── 1_create_servers.yml     # Provision Hetzner Cloud servers
│   ├── 2_install_kafka.yml      # Install Kafka in KRaft mode
│   ├── 3_build_and_deploy_artifact.yml  # Build & deploy trading app
│   ├── 4_manage_artifact.yml    # Manage trading app (list/run/kill)
│   ├── 5_manage_kafka.yml       # Manage Kafka instances
│   └── 6_monitor_pipeline_performance.yml  # Monitor system performance
├── config/kafka/                # Kafka configuration files
│   ├── server.properties        # KRaft mode configuration
│   └── kafka.service            # Systemd service definition
└── scripts/                     # Automation scripts
    ├── hetzner/                 # Hetzner Cloud management
    │   ├── create_server.py     # Server creation
    │   ├── delete_server.py     # Server deletion
    │   ├── firewall.py          # Firewall configuration
    │   └── utils.py             # Common utilities
    ├── kafka/
    │   └── install_kafka.sh     # Kafka installation script
    ├── monitor/                 # Performance monitoring scripts
    │   ├── kafka_infrastructure.sh
    │   ├── pipeline_monitor.sh
    │   └── topic_analysis.sh
    └── python/                  # Trading artifact management
        ├── install_artifact.sh
        └── run_artifact.sh
```

## Features

- **Automated Deployment Pipeline**: Sequential GitHub Actions workflows for complete setup
- **Kafka in KRaft Mode**: No ZooKeeper dependency, simplified architecture
- **Hetzner Cloud Integration**: Automatic server provisioning with firewall configuration
- **Trading Application Support**: Build, deploy, and manage trading artifacts
- **Performance Monitoring**: Real-time pipeline and system monitoring tools
- **External Access**: Properly configured networking for remote connections

## Workflows

The deployment process is split into 6 sequential workflows:

1. **Server Creation** - Provisions Hetzner Cloud servers with SSH keys and firewall rules
2. **Kafka Installation** - Installs and configures Kafka in KRaft mode using systemd
3. **Build & Deploy Artifact** - Builds trading application from specified version tag
4. **Manage Artifact** - Controls trading application lifecycle (list/run/kill processes)
5. **Manage Kafka** - Manages Kafka instances and server operations
6. **Monitor Performance** - Analyzes topic lag, throughput, and system metrics

## Configuration

- **`config/kafka/`** - Kafka KRaft configuration and systemd service files
- **Workflow Inputs** - Customizable parameters for server specs, versions, and operations
- **GitHub Secrets** - Secure storage for `HCLOUD_TOKEN` and SSH keys

## Prerequisites

1. [Hetzner Cloud](https://www.hetzner.com/cloud) account with API token
2. GitHub repository with this code
3. Trading application repository (for artifact deployment)

## Quick Start

1. Fork this repository
2. Add `HCLOUD_TOKEN` as a GitHub secret
3. Run workflows sequentially (1 → 2 → 3 → 4/5/6 as needed)
4. Server credentials are saved as workflow artifacts

## Scripts Overview

- **`scripts/hetzner/`** - Server lifecycle management (create, delete, firewall setup)
- **`scripts/kafka/`** - Kafka installation and KRaft mode configuration  
- **`scripts/monitor/`** - Performance analysis tools for lag, throughput, and system health
- **`scripts/python/`** - Trading application deployment and process management

## Useful Resources

### Hetzner Resources
- [Hetzner Community Tutorials](https://community.hetzner.com/tutorials)
- [Hetzner Cloud GitHub Organization](https://github.com/hetznercloud)
- [Hetzner Cloud CLI](https://github.com/hetznercloud/cli)
- [Hetzner Cloud GitHub Action](https://github.com/hetznercloud/setup-hcloud)
- [Hetzner Cloud Python Library](https://github.com/hetznercloud/hcloud-python)

### Kafka Resources
- [Apache Kafka Documentation](https://kafka.apache.org/documentation/)
- [Kafka KRaft Mode Documentation](https://kafka.apache.org/documentation/#kraft)

## License and Disclaimer

This project is released into the public domain. You are free to:
- Use, copy, modify, and distribute the code
- Use the code for commercial or non-commercial purposes
- Apply any license of your choice to derivatives of this code

### Disclaimer

**THIS SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED.**

This project is intended for educational and tutorial purposes only. It is not recommended for production use without additional security hardening and thorough testing.

The author(s) of this project shall not be liable for any damages or liability arising from the use of this software. Use at your own risk.

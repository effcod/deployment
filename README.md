# Hetzner Kafka Deployment

Automated deployment of Apache Kafka in KRaft mode (without ZooKeeper) on Hetzner Cloud servers using GitHub Actions.

## Project Structure

```
kafka-deployment/
├── .github/
│   └── workflows/
│       └── create_servers.yml
│       └── install_kafka.yml
│       └── manage.yml
├── config/
│   └── kafka/
│       ├── server.properties    # Kafka KRaft configuration
│       └── kafka.service        # Systemd service file
├── scripts/
│   ├── hetzner/
│   │   └── create_server.py
│   │   └── delete_server.py
│   │   └── utils.py
│   └── kafka/
│       └── install_kafka.sh     # Kafka installation script
```

## Features

- One-click deployment via GitHub Actions
- Uses Kafka in KRaft mode (no ZooKeeper needed)
- Automatic server provisioning on Hetzner Cloud
- Verification steps to ensure proper deployment
- External access configured automatically

## Prerequisites

1. [Hetzner Cloud](https://www.hetzner.com/cloud) account
2. API token with read/write permissions
3. GitHub repository with this code

## Usage

1. Fork/clone this repository
2. Add your Hetzner Cloud API token as a GitHub secret named `HCLOUD_TOKEN`
3. Run the GitHub Action workflow
4. Server credentials will be securely saved as artifacts

## Configuration

The deployment can be customized via:
- GitHub Actions workflow inputs
- Kafka configuration files in the `config/kafka` directory

## Development

To contribute or modify:
1. Clone the repository
2. Install dependencies: `pip install -r requirements.txt`
3. Make changes
4. Test locally if possible
5. Submit a pull request

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

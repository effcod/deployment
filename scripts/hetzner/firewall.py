from hcloud import Client
from hcloud.firewalls.domain import Firewall, FirewallRule
import sys

def set_firewall(api_token, allowed_ips):
    # Initialize Hetzner client
    client = Client(token=api_token)

    # Define firewall rules to allow only the specified IPs
    rules = [
        FirewallRule(direction='in', protocol='tcp', port='1-65535', source_ips=allowed_ips),
        FirewallRule(direction='in', protocol='udp', port='1-65535', source_ips=allowed_ips),
        FirewallRule(direction='in', protocol='icmp', source_ips=allowed_ips)
    ]

    # Retrieve all servers
    servers = client.servers.get_all()

    for server in servers:
        firewall_name = f'firewall-{server.name}'
        firewalls = client.firewalls.get_all(name=firewall_name)

        if firewalls:
            # Update existing firewall
            firewall = firewalls[0]
            firewall.update(rules=rules).wait_until_finished()
        else:
            # Create and apply a new firewall
            client.firewalls.create(
                name=firewall_name,
                rules=rules,
                apply_to=[{'type': 'server', 'server': {'id': server.id}}]
            )
        print(f'🔒 Firewall configured for server: {server.name}')

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python set_firewall.py <HCLOUD_TOKEN> <allowed_ips_comma_separated>")
        sys.exit(1)

    api_token = sys.argv[1]
    allowed_ips = sys.argv[2].split(",")
    set_firewall(api_token, [ip.strip() for ip in allowed_ips])

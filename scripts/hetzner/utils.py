from hcloud import Client

def get_hcloud_client(token):
    """Create and return an authenticated Hetzner Cloud client"""
    if not token:
        raise ValueError("HCLOUD_TOKEN is required but not provided or empty")
    return Client(token=token)

import os
from utils import get_hcloud_client

def get_server_config():
    """Read server configuration from environment variables with defaults"""
    config = {
        "token": os.environ.get("HCLOUD_TOKEN"),
        "name": os.environ.get("HCLOUD_SERVER_NAME")  # can be None
    }
    
    if not config["token"]:
        print("Error: HCLOUD_TOKEN environment variable is not set")
        exit(1)
    
    return config

def delete_hcloud_server(token, name=None):
    """Delete a Hetzner Cloud server with the given name
    If name is None, delete all servers
    """
    client = get_hcloud_client(token)
    servers = client.servers.get_all()
    
    if not servers:
        print("No servers found in your Hetzner account.")
        return False
    
    if name is None:
        # Delete all servers
        print(f"No specific server name provided. Deleting ALL {len(servers)} servers...")
        for server in servers:
            print(f"Stopping and deleting server '{server.name}' (ID: {server.id}, IP: {server.public_net.ipv4.ip})...")
            try:
                # First try to shutdown gracefully
                server.shutdown()
                print(f"Server '{server.name}' shutdown initiated.")
                # Then delete
                client.servers.delete(server)
                print(f"Server '{server.name}' deleted successfully.")
            except Exception as e:
                print(f"Error deleting server '{server.name}': {e}")
        return True
    else:
        # Delete specific server
        print(f"Looking for server '{name}'...")
        for server in servers:
            if server.name == name:
                print(f"Found server '{name}' (ID: {server.id}, IP: {server.public_net.ipv4.ip})")
                print(f"Stopping and deleting server '{name}'...")
                try:
                    # First try to shutdown gracefully
                    server.shutdown()
                    print(f"Server '{name}' shutdown initiated.")
                    # Then delete
                    client.servers.delete(server)
                    print(f"Server '{name}' deleted successfully.")
                    return True
                except Exception as e:
                    print(f"Error deleting server '{name}': {e}")
                    return False
        
        print(f"Server '{name}' not found.")
        return False

if __name__ == "__main__":
    config = get_server_config()
    
    try:
        if config["name"]:
            print(f"Using configuration: Server name='{config['name']}'")
        else:
            print("No server name specified, will delete ALL servers")
            
        delete_hcloud_server(token=config['token'], name=config['name'])
    except Exception as e:
        print(f"Error: {e}")
        exit(1)
from hcloud.images.domain import Image
from hcloud.server_types.domain import ServerType
import os
import time
from utils import get_hcloud_client

def get_server_config():
    """Read server configuration from environment variables with defaults"""
    token = os.environ.get("HCLOUD_TOKEN")
    if not token:
        print("Error: HCLOUD_TOKEN environment variable is not set")
        exit(1)
    
    # Try to get timeout from env var, default to 5 minutes (300 seconds)
    try:
        max_wait_time = int(os.environ.get("HCLOUD_SERVER_WAIT_TIMEOUT", "120"))
    except ValueError:
        print("Warning: Invalid HCLOUD_SERVER_WAIT_TIMEOUT value, using default of 120 seconds")
        max_wait_time = 120
    
    config = {
        "token": token,
        "name": os.environ.get("HCLOUD_SERVER_NAME", "my-app-server"),
        "server_type": os.environ.get("HCLOUD_SERVER_TYPE", "cx22"),
        "image": os.environ.get("HCLOUD_IMAGE", "ubuntu-24.04"),
        "ssh_key_name": os.environ.get("HCLOUD_SSH_KEY_NAME", None),
        "max_wait_time": max_wait_time
    }
    return config

def create_hcloud_server(token, name, server_type, image, ssh_key_name=None, max_wait_time=300):
    """Create a Hetzner Cloud server with the given parameters"""
    client = get_hcloud_client(token)
    
    print(f"Creating server '{name}' with type '{server_type}' and image '{image}'...")
    
    # Prepare server creation parameters
    create_params = {
        "name": name,
        "server_type": ServerType(name=server_type),
        "image": Image(name=image),
    }
    
    # Add SSH key if provided
    if ssh_key_name:
        print(f"Using SSH key: {ssh_key_name}")
        ssh_key = client.ssh_keys.get_by_name(ssh_key_name)
        if ssh_key:
            create_params["ssh_keys"] = [ssh_key]
        else:
            print(f"Warning: SSH key '{ssh_key_name}' not found. Server will be created with password authentication.")
    
    # Capture the full response
    response = client.servers.create(**create_params)
    
    # Get the server object and root password (if no SSH key was used)
    server = response.server
    root_password = response.root_password  # Will be None if SSH key was used

    print(f"Server created with ID: {server.id}")
    
    # Wait for server to be ready with timeout
    start_time = time.time()
    print(f"Waiting for server to become ready (timeout: {max_wait_time} seconds)...")
    
    while True:
        # Check if timeout exceeded
        elapsed_time = time.time() - start_time
        if elapsed_time > max_wait_time:
            raise TimeoutError(f"Server did not reach 'running' status within {max_wait_time} seconds. Last status: {server.status}")
        
        server = client.servers.get_by_id(server.id)
        elapsed_formatted = f"{elapsed_time:.1f}"
        print(f"Server status: {server.status} (waited {elapsed_formatted}s, timeout: {max_wait_time}s)")
        
        if server.status == "running":
            print(f"Server is ready after {elapsed_formatted} seconds")
            return server, root_password  # Return both server and password
        
        time.sleep(5)

if __name__ == "__main__":
    config = get_server_config()
    
    try:
        print(f"Using configuration: Server name='{config['name']}', type='{config['server_type']}', image='{config['image']}', ssh_key='{config['ssh_key_name']}', timeout={config['max_wait_time']}s")
        
        # Get both server and root_password from the function
        server, root_password = create_hcloud_server(
            token=config["token"],
            name=config["name"],
            server_type=config["server_type"],
            image=config["image"],
            ssh_key_name=config["ssh_key_name"],
            max_wait_time=config["max_wait_time"]
        )
        
        # Output in GitHub Actions compatible format
        print(f"SERVER_IP={server.public_net.ipv4.ip}")
        if root_password:
            print(f"ROOT_PASS={root_password}")
        else:
            print("Using SSH key authentication (no password)")
        
        # Also print for human readability in logs
        print(f"Server deployed successfully at IP: {server.public_net.ipv4.ip}")
    except ValueError as e:
        print(f"Runtime Error: {e}")
        exit(1)
    except TimeoutError as e:
        print(f"Timeout Error: {e}")
        exit(2)

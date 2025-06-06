import os
from utils import get_hcloud_client

def create_ssh_key():
    """
    Create an SSH key in Hetzner Cloud using the provided public key.
    Returns the SSH key ID or name that can be used when creating servers.
    """
    # Get required environment variables
    token = os.environ.get("HCLOUD_TOKEN")
    if not token:
        print("Error: HCLOUD_TOKEN environment variable is not set")
        exit(1)
    
    key_name = os.environ.get("SSH_KEY_NAME")
    if not key_name:
        print("Error: SSH_KEY_NAME environment variable is not set")
        exit(1)
    
    public_key = os.environ.get("SSH_PUBLIC_KEY")
    if not public_key:
        print("Error: SSH_PUBLIC_KEY environment variable is not set")
        exit(1)
    
    # Initialize Hetzner Cloud client
    client = get_hcloud_client(token)
    
    # Check if a key with this name already exists
    try:
        existing_key = client.ssh_keys.get_by_name(key_name)
        if (existing_key):
            print(f"SSH key with name '{key_name}' already exists, deleting it...")
            # Delete the existing key
            existing_key.delete()
            print(f"Existing SSH key deleted")
    except Exception as e:
        # Key doesn't exist or error occurred, we'll proceed to create a new one
        print(f"Note: {str(e)}")
    
    # Create new SSH key
    try:
        print(f"Creating new SSH key '{key_name}'...")
        response = client.ssh_keys.create(name=key_name, public_key=public_key)
        # The response structure might vary depending on the library version
        # Let's handle different possible structures
        if hasattr(response, 'ssh_key'):
            print(f"SSH key created successfully: {response.ssh_key.name}")
            return response.ssh_key.name
        else:
            # Direct response object is the SSH key
            print(f"SSH key created successfully: {response.name}")
            return response.name
    except Exception as e:
        print(f"Error creating SSH key: {e}")
        exit(1)

if __name__ == "__main__":
    key_name = create_ssh_key()
    print(f"SSH_KEY_NAME={key_name}")

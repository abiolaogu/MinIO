"""
Example usage of MinIO Enterprise Python SDK

This script demonstrates all the key features of the SDK including:
- Health checks and server info
- Uploading objects
- Listing objects with prefix filtering
- Downloading objects
- Deleting objects
"""

from minio_sdk import MinIOClient, Config, MinIOError


def main():
    # Create client configuration
    config = Config(
        base_url="http://localhost:9000",
        tenant_id="550e8400-e29b-41d4-a716-446655440000",
        timeout=30,
        max_retries=3,
        base_delay=1.0
    )

    # Use context manager for automatic cleanup
    with MinIOClient(config) as client:
        # Example 1: Health check
        print("=== Health Check ===")
        try:
            healthy = client.health_check()
            if healthy:
                print("✓ Server is healthy")
            else:
                print("✗ Server is not healthy")
        except MinIOError as e:
            print(f"Health check failed: {e}")

        # Example 2: Get server info
        print("\n=== Server Info ===")
        try:
            info = client.get_server_info()
            print(f"Status: {info.status}")
            print(f"Version: {info.version}")
            print(f"Performance: {info.performance}")
        except MinIOError as e:
            print(f"Failed to get server info: {e}")

        # Example 3: Upload objects
        print("\n=== Upload Objects ===")
        files = {
            "documents/report.txt": b"Annual Report 2024",
            "images/photo.jpg": b"Binary image data...",
            "config/settings.json": b'{"setting": "value"}',
        }

        for key, data in files.items():
            try:
                resp = client.upload(key, data)
                print(f"✓ Uploaded: {resp.key} ({resp.size} bytes, status: {resp.status})")
            except MinIOError as e:
                print(f"✗ Failed to upload {key}: {e}")

        # Example 4: List all objects
        print("\n=== List Objects ===")
        try:
            keys = client.list()
            print(f"Found {len(keys)} objects:")
            for i, key in enumerate(keys, 1):
                print(f"  {i}. {key}")
        except MinIOError as e:
            print(f"Failed to list objects: {e}")

        # Example 5: List with prefix
        print("\n=== List Objects with Prefix 'documents/' ===")
        try:
            doc_keys = client.list(prefix="documents/")
            print(f"Found {len(doc_keys)} documents:")
            for i, key in enumerate(doc_keys, 1):
                print(f"  {i}. {key}")
        except MinIOError as e:
            print(f"Failed to list documents: {e}")

        # Example 6: Download objects
        print("\n=== Download Objects ===")
        for key in files.keys():
            try:
                data = client.download(key)
                print(f"✓ Downloaded: {key} ({len(data)} bytes)")

                # For text files, print a preview
                if len(data) < 100:
                    try:
                        preview = data.decode('utf-8')
                        print(f"  Preview: {preview}")
                    except UnicodeDecodeError:
                        print(f"  Preview: [Binary data]")
            except MinIOError as e:
                print(f"✗ Failed to download {key}: {e}")

        # Example 7: Delete objects
        print("\n=== Delete Objects ===")
        for key in files.keys():
            try:
                client.delete(key)
                print(f"✓ Deleted: {key}")
            except MinIOError as e:
                print(f"✗ Failed to delete {key}: {e}")

        # Example 8: Verify deletion
        print("\n=== Verify Deletion ===")
        try:
            keys_after = client.list()
            print(f"Objects remaining: {len(keys_after)}")
        except MinIOError as e:
            print(f"Failed to list objects: {e}")

        print("\n=== Example Complete ===")


if __name__ == "__main__":
    main()

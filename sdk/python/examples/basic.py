"""Basic example of using MinIO Enterprise Python SDK"""

from minio_enterprise import Client, Config

def main():
    # Create a client
    client = Client(Config(
        base_url="http://localhost:9000",
        tenant_id="550e8400-e29b-41d4-a716-446655440000"
    ))

    try:
        # Example 1: Upload a text object
        print("=== Example 1: Upload a text object ===")
        text_data = b"Hello, MinIO Enterprise! This is a test file."
        response = client.upload("hello.txt", text_data)

        print("✓ Uploaded successfully")
        print(f"  Key: {response['key']}")
        print(f"  Size: {response['size']} bytes")
        print(f"  Status: {response['status']}\n")

        # Example 2: Download the object
        print("=== Example 2: Download the object ===")
        data = client.download("hello.txt")

        print("✓ Downloaded successfully")
        print(f"  Content: {data.decode()}\n")

        # Example 3: Get server information
        print("=== Example 3: Server Information ===")
        info = client.get_server_info()

        print("✓ Server Info:")
        print(f"  Status: {info['status']}")
        print(f"  Version: {info['version']}")
        print(f"  Performance: {info['performance']} improvement\n")

        # Example 4: Health check
        print("=== Example 4: Health Check ===")
        if client.health_check():
            print("✓ Service is healthy!\n")

        print("All examples completed successfully!")

    finally:
        client.close()


if __name__ == "__main__":
    main()

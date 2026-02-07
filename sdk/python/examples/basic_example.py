"""Basic usage example for MinIO Enterprise Python SDK"""

from minio_enterprise import (
    Client,
    Config,
    UploadRequest,
    DownloadRequest,
    DeleteRequest,
    ListRequest,
    QuotaRequest,
    MinIOError,
)


def main():
    # Create a new MinIO client
    print("Creating MinIO client...")
    client = Client(Config(
        base_url="http://localhost:9000",
        api_key="your-api-key-here",
        timeout=30,
        max_retries=3,
    ))

    try:
        # Example 1: Health Check
        print("\n=== Health Check ===")
        try:
            health = client.health_check()
            print(f"Status: {health['status']}")
        except MinIOError as e:
            print(f"Health check failed: {e}")

        # Example 2: Upload a file
        print("\n=== Upload File ===")
        try:
            upload_response = client.upload(UploadRequest(
                tenant_id="tenant-123",
                object_id="example-file.txt",
                data=b"Hello, MinIO Enterprise!",
            ))
            print(f"Message: {upload_response['message']}")
            print(f"Size: {upload_response['size']} bytes")
        except MinIOError as e:
            print(f"Upload failed: {e}")

        # Example 3: Download the file
        print("\n=== Download File ===")
        try:
            download_response = client.download(DownloadRequest(
                tenant_id="tenant-123",
                object_id="example-file.txt",
            ))
            print(f"Message: {download_response['message']}")
            print(f"Size: {download_response['size']} bytes")
            print(f"Data: {download_response['data']}")
        except MinIOError as e:
            print(f"Download failed: {e}")

        # Example 4: List objects
        print("\n=== List Objects ===")
        try:
            list_response = client.list(ListRequest(
                tenant_id="tenant-123",
                limit=10,
            ))
            print(f"Found {list_response['count']} objects:")
            for i, obj in enumerate(list_response['objects'], 1):
                print(f"  {i}. {obj['object_id']} ({obj['size']} bytes)")
        except MinIOError as e:
            print(f"List failed: {e}")

        # Example 5: Get quota information
        print("\n=== Get Quota ===")
        try:
            quota_response = client.get_quota(QuotaRequest(
                tenant_id="tenant-123",
            ))
            print(f"Used: {quota_response['used']} bytes")
            print(f"Limit: {quota_response['limit']} bytes")
            print(f"Available: {quota_response['available']} bytes")
            usage_percent = (quota_response['used'] / quota_response['limit']) * 100
            print(f"Usage: {usage_percent:.2f}%")
        except MinIOError as e:
            print(f"Get quota failed: {e}")

        # Example 6: Delete the file
        print("\n=== Delete File ===")
        try:
            delete_response = client.delete(DeleteRequest(
                tenant_id="tenant-123",
                object_id="example-file.txt",
            ))
            print(f"Message: {delete_response['message']}")
        except MinIOError as e:
            print(f"Delete failed: {e}")

        print("\nAll examples completed!")

    finally:
        # Clean up
        client.close()


def context_manager_example():
    """Example using context manager"""
    print("\n=== Context Manager Example ===")

    # Using 'with' statement automatically closes the client
    with Client(Config(
        base_url="http://localhost:9000",
        api_key="your-api-key",
    )) as client:
        try:
            response = client.health_check()
            print(f"Health status: {response['status']}")
        except MinIOError as e:
            print(f"Error: {e}")

    print("Client automatically closed")


if __name__ == "__main__":
    main()
    context_manager_example()

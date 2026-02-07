"""
Basic upload example for MinIO Enterprise Python SDK
"""

import os
from minio_enterprise import Client, MinIOError, QuotaExceededError


def get_env(key: str, default: str) -> str:
    """Get environment variable or return default"""
    return os.getenv(key, default)


def main():
    # Initialize client with configuration from environment variables
    client = Client(
        endpoint=get_env("MINIO_ENDPOINT", "http://localhost:9000"),
        api_key=get_env("MINIO_API_KEY", "your-api-key"),
        api_secret=get_env("MINIO_API_SECRET", "your-api-secret"),
        tenant_id=get_env("MINIO_TENANT_ID", "your-tenant-id"),
    )

    try:
        # Example 1: Upload a simple text file
        print("Example 1: Uploading a text file...")
        text_data = b"Hello, MinIO Enterprise! This is a test file."
        client.upload("my-bucket", "hello.txt", text_data)
        print("✓ Upload successful: hello.txt")

        # Example 2: Download the file
        print("\nExample 2: Downloading the file...")
        data = client.download("my-bucket", "hello.txt")
        print(f"✓ Download successful: {data.decode('utf-8')}")

        # Example 3: Upload multiple files
        print("\nExample 3: Uploading multiple files...")
        files = {
            "file1.txt": b"Content of file 1",
            "file2.txt": b"Content of file 2",
            "file3.txt": b"Content of file 3",
        }

        for filename, content in files.items():
            try:
                client.upload("my-bucket", filename, content)
                print(f"✓ Uploaded: {filename}")
            except MinIOError as e:
                print(f"✗ Failed to upload {filename}: {e}")

        # Example 4: List all files in the bucket
        print("\nExample 4: Listing all files in bucket...")
        objects = client.list("my-bucket")
        print(f"✓ Found {len(objects)} objects:")
        for obj in objects:
            print(f"  - {obj['key']} (size: {obj['size']} bytes)")

        # Example 5: List files with prefix
        print("\nExample 5: Listing files with prefix 'file'...")
        objects = client.list("my-bucket", prefix="file")
        print(f"✓ Found {len(objects)} objects with prefix 'file':")
        for obj in objects:
            print(f"  - {obj['key']}")

        # Example 6: Check quota
        print("\nExample 6: Checking quota...")
        quota = client.get_quota()
        print(f"✓ Quota Info:")
        print(f"  - Used: {quota['used']} bytes")
        print(f"  - Limit: {quota['limit']} bytes")
        print(f"  - Usage: {quota['percentage']:.2f}%")

        # Example 7: Delete a file
        print("\nExample 7: Deleting a file...")
        client.delete("my-bucket", "file3.txt")
        print("✓ Delete successful: file3.txt")

        # Example 8: Verify deletion
        print("\nExample 8: Verifying deletion...")
        objects = client.list("my-bucket")
        remaining = [obj['key'] for obj in objects]
        print(f"✓ Remaining objects: {remaining}")

        # Example 9: Health check
        print("\nExample 9: Checking service health...")
        health = client.health()
        print(f"✓ Service Status: {health['status']}")
        print(f"  Timestamp: {health['timestamp']}")

        print("\n✅ All examples completed successfully!")

    except QuotaExceededError as e:
        print(f"\n❌ Quota exceeded: {e}")
    except MinIOError as e:
        print(f"\n❌ MinIO error: {e}")
    except Exception as e:
        print(f"\n❌ Unexpected error: {e}")
    finally:
        client.close()


def example_context_manager():
    """Example using context manager for automatic cleanup"""
    print("\nContext Manager Example:")
    with Client(
        endpoint="http://localhost:9000",
        api_key="your-api-key",
        api_secret="your-api-secret",
        tenant_id="your-tenant-id",
    ) as client:
        # Upload file
        client.upload("my-bucket", "context-test.txt", b"Hello from context manager!")
        print("✓ Uploaded using context manager")

        # Download file
        data = client.download("my-bucket", "context-test.txt")
        print(f"✓ Downloaded: {data.decode('utf-8')}")

    # Client automatically closed when exiting context
    print("✓ Client automatically closed")


if __name__ == "__main__":
    main()
    example_context_manager()

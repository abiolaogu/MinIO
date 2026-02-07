"""Advanced example demonstrating error handling and file operations"""

from minio_enterprise import Client, Config, APIError, NetworkError


def example_error_handling():
    """Demonstrate error handling"""
    print("=== Example: Error Handling ===")

    client = Client(Config(
        base_url="http://localhost:9000",
        tenant_id="550e8400-e29b-41d4-a716-446655440000"
    ))

    try:
        # Try to download a non-existent file
        data = client.download("non-existent-file.txt")
    except APIError as e:
        if e.status_code == 404:
            print(f"✓ Correctly handled 404 error: {e.message}")
        elif e.status_code == 403:
            print(f"✗ Quota exceeded: {e.message}")
        else:
            print(f"✗ API error {e.status_code}: {e.message}")
    except NetworkError as e:
        print(f"✗ Network error: {e.message}")
    finally:
        client.close()

    print()


def example_file_operations():
    """Demonstrate file upload and download"""
    print("=== Example: File Operations ===")

    client = Client(Config(
        base_url="http://localhost:9000",
        tenant_id="550e8400-e29b-41d4-a716-446655440000"
    ))

    try:
        # Create a test file
        test_file = "/tmp/test-upload.txt"
        with open(test_file, "w") as f:
            f.write("This is a test file for MinIO Enterprise!\n")
            f.write("Second line of content.\n")

        # Upload the file
        with open(test_file, "rb") as f:
            response = client.upload("uploaded-file.txt", f)
            print(f"✓ Uploaded file: {response['key']} ({response['size']} bytes)")

        # Download to a different file
        download_file = "/tmp/test-download.txt"
        client.download_to_file("uploaded-file.txt", download_file)
        print(f"✓ Downloaded to: {download_file}")

        # Verify content
        with open(download_file, "r") as f:
            content = f.read()
            print(f"✓ Content verified: {len(content)} characters")

    finally:
        client.close()

    print()


def example_context_manager():
    """Demonstrate context manager usage"""
    print("=== Example: Context Manager ===")

    with Client(Config(
        base_url="http://localhost:9000",
        tenant_id="550e8400-e29b-41d4-a716-446655440000"
    )) as client:
        # Upload some data
        response = client.upload("context-test.txt", b"Context manager example")
        print(f"✓ Uploaded using context manager: {response['key']}")

    # Client automatically closes when exiting context
    print("✓ Client automatically closed\n")


def main():
    """Run all advanced examples"""
    example_error_handling()
    example_file_operations()
    example_context_manager()

    print("All advanced examples completed!")


if __name__ == "__main__":
    main()

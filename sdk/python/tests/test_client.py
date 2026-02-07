"""Unit tests for MinIO Enterprise Python SDK"""

import pytest
import responses
from minio_enterprise import Client, Config, APIError, NetworkError


@pytest.fixture
def client():
    """Create a test client"""
    return Client(Config(
        base_url="http://localhost:9000",
        tenant_id="test-tenant-id"
    ))


def test_client_creation():
    """Test client creation with valid config"""
    client = Client(Config(
        base_url="http://localhost:9000",
        tenant_id="test-tenant"
    ))
    assert client.config.base_url == "http://localhost:9000"
    assert client.config.tenant_id == "test-tenant"
    client.close()


def test_client_creation_invalid():
    """Test client creation with invalid config"""
    with pytest.raises(ValueError):
        Client(Config(base_url="", tenant_id="test"))

    with pytest.raises(ValueError):
        Client(Config(base_url="http://localhost:9000", tenant_id=""))


@responses.activate
def test_upload(client):
    """Test upload operation"""
    responses.add(
        responses.PUT,
        "http://localhost:9000/upload?key=test.txt",
        json={"status": "uploaded", "key": "test.txt", "size": 9},
        status=200
    )

    response = client.upload("test.txt", b"test data")
    assert response["status"] == "uploaded"
    assert response["key"] == "test.txt"
    assert response["size"] == 9

    # Verify headers
    assert len(responses.calls) == 1
    assert responses.calls[0].request.headers["X-Tenant-ID"] == "test-tenant-id"


@responses.activate
def test_upload_error(client):
    """Test upload with API error"""
    responses.add(
        responses.PUT,
        "http://localhost:9000/upload?key=test.txt",
        json={"error": "Quota exceeded"},
        status=403
    )

    with pytest.raises(APIError) as exc_info:
        client.upload("test.txt", b"test data")

    assert exc_info.value.status_code == 403
    assert exc_info.value.message == "Quota exceeded"


@responses.activate
def test_download(client):
    """Test download operation"""
    test_data = b"Hello, MinIO!"

    responses.add(
        responses.GET,
        "http://localhost:9000/download?key=test.txt",
        body=test_data,
        status=200,
        content_type="application/octet-stream"
    )

    data = client.download("test.txt")
    assert data == test_data


@responses.activate
def test_download_not_found(client):
    """Test download with 404 error"""
    responses.add(
        responses.GET,
        "http://localhost:9000/download?key=missing.txt",
        json={"error": "Object not found"},
        status=404
    )

    with pytest.raises(APIError) as exc_info:
        client.download("missing.txt")

    assert exc_info.value.status_code == 404
    assert exc_info.value.message == "Object not found"


@responses.activate
def test_get_server_info(client):
    """Test get server info"""
    responses.add(
        responses.GET,
        "http://localhost:9000/",
        json={
            "status": "ok",
            "version": "3.0.0",
            "performance": "100x"
        },
        status=200
    )

    info = client.get_server_info()
    assert info["status"] == "ok"
    assert info["version"] == "3.0.0"
    assert info["performance"] == "100x"


@responses.activate
def test_health_check(client):
    """Test health check"""
    responses.add(
        responses.GET,
        "http://localhost:9000/minio/health/ready",
        body="READY",
        status=200
    )

    result = client.health_check()
    assert result is True


@responses.activate
def test_health_check_failure(client):
    """Test health check failure"""
    responses.add(
        responses.GET,
        "http://localhost:9000/minio/health/ready",
        body="Service unavailable",
        status=503
    )

    with pytest.raises(APIError) as exc_info:
        client.health_check()

    assert exc_info.value.status_code == 503


def test_context_manager():
    """Test context manager usage"""
    with Client(Config(
        base_url="http://localhost:9000",
        tenant_id="test-tenant"
    )) as client:
        assert client.config.tenant_id == "test-tenant"
    # Session should be closed after exiting context


def test_custom_config():
    """Test client with custom configuration"""
    client = Client(Config(
        base_url="http://localhost:9000",
        tenant_id="test-tenant",
        timeout=60,
        max_retries=5
    ))

    assert client.config.timeout == 60
    assert client.config.max_retries == 5
    client.close()

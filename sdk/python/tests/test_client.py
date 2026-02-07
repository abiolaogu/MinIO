"""Unit tests for MinIO Enterprise Python SDK"""

import pytest
from minio_enterprise import (
    Client,
    Config,
    UploadRequest,
    DownloadRequest,
    DeleteRequest,
    ListRequest,
    QuotaRequest,
    MinIOError,
    MinIOConnectionError,
    MinIOValidationError,
    MinIOAPIError,
)


class TestConfig:
    """Test Config class"""

    def test_valid_config(self):
        """Test valid configuration"""
        config = Config(
            base_url="http://localhost:9000",
            api_key="test-key",
        )
        assert config.base_url == "http://localhost:9000"
        assert config.api_key == "test-key"
        assert config.timeout == 30
        assert config.max_retries == 3

    def test_custom_config(self):
        """Test custom configuration"""
        config = Config(
            base_url="http://localhost:9000",
            api_key="test-key",
            timeout=60,
            max_retries=5,
        )
        assert config.timeout == 60
        assert config.max_retries == 5

    def test_missing_base_url(self):
        """Test missing base URL"""
        with pytest.raises(MinIOValidationError):
            Config(base_url="")

    def test_trailing_slash_removed(self):
        """Test trailing slash is removed from base URL"""
        config = Config(base_url="http://localhost:9000/")
        assert config.base_url == "http://localhost:9000"


class TestClient:
    """Test Client class"""

    def test_client_creation(self):
        """Test client creation"""
        config = Config(base_url="http://localhost:9000", api_key="test-key")
        client = Client(config)
        assert client.config == config
        assert client.session is not None
        client.close()

    def test_context_manager(self):
        """Test client as context manager"""
        config = Config(base_url="http://localhost:9000", api_key="test-key")
        with Client(config) as client:
            assert client.session is not None
        # Session should be closed after context exit


class TestUploadRequest:
    """Test UploadRequest class"""

    def test_valid_request(self):
        """Test valid upload request"""
        req = UploadRequest(
            tenant_id="tenant-123",
            object_id="file.txt",
            data=b"test data",
        )
        assert req.tenant_id == "tenant-123"
        assert req.object_id == "file.txt"
        assert req.data == b"test data"

    def test_missing_tenant_id(self):
        """Test missing tenant_id"""
        with pytest.raises(MinIOValidationError):
            UploadRequest(tenant_id="", object_id="file.txt", data=b"data")

    def test_missing_object_id(self):
        """Test missing object_id"""
        with pytest.raises(MinIOValidationError):
            UploadRequest(tenant_id="tenant-123", object_id="", data=b"data")


class TestDownloadRequest:
    """Test DownloadRequest class"""

    def test_valid_request(self):
        """Test valid download request"""
        req = DownloadRequest(tenant_id="tenant-123", object_id="file.txt")
        assert req.tenant_id == "tenant-123"
        assert req.object_id == "file.txt"

    def test_missing_tenant_id(self):
        """Test missing tenant_id"""
        with pytest.raises(MinIOValidationError):
            DownloadRequest(tenant_id="", object_id="file.txt")

    def test_missing_object_id(self):
        """Test missing object_id"""
        with pytest.raises(MinIOValidationError):
            DownloadRequest(tenant_id="tenant-123", object_id="")


class TestDeleteRequest:
    """Test DeleteRequest class"""

    def test_valid_request(self):
        """Test valid delete request"""
        req = DeleteRequest(tenant_id="tenant-123", object_id="file.txt")
        assert req.tenant_id == "tenant-123"
        assert req.object_id == "file.txt"

    def test_missing_tenant_id(self):
        """Test missing tenant_id"""
        with pytest.raises(MinIOValidationError):
            DeleteRequest(tenant_id="", object_id="file.txt")

    def test_missing_object_id(self):
        """Test missing object_id"""
        with pytest.raises(MinIOValidationError):
            DeleteRequest(tenant_id="tenant-123", object_id="")


class TestListRequest:
    """Test ListRequest class"""

    def test_valid_request(self):
        """Test valid list request"""
        req = ListRequest(tenant_id="tenant-123", limit=10)
        assert req.tenant_id == "tenant-123"
        assert req.limit == 10
        assert req.prefix is None

    def test_with_prefix(self):
        """Test list request with prefix"""
        req = ListRequest(tenant_id="tenant-123", prefix="folder/", limit=50)
        assert req.prefix == "folder/"
        assert req.limit == 50

    def test_default_limit(self):
        """Test default limit"""
        req = ListRequest(tenant_id="tenant-123")
        assert req.limit == 100

    def test_missing_tenant_id(self):
        """Test missing tenant_id"""
        with pytest.raises(MinIOValidationError):
            ListRequest(tenant_id="")


class TestQuotaRequest:
    """Test QuotaRequest class"""

    def test_valid_request(self):
        """Test valid quota request"""
        req = QuotaRequest(tenant_id="tenant-123")
        assert req.tenant_id == "tenant-123"

    def test_missing_tenant_id(self):
        """Test missing tenant_id"""
        with pytest.raises(MinIOValidationError):
            QuotaRequest(tenant_id="")


class TestExceptions:
    """Test custom exceptions"""

    def test_minio_error(self):
        """Test base MinIOError"""
        error = MinIOError("Test error")
        assert str(error) == "Test error"

    def test_connection_error(self):
        """Test MinIOConnectionError"""
        error = MinIOConnectionError("Connection failed")
        assert str(error) == "Connection failed"
        assert isinstance(error, MinIOError)

    def test_validation_error(self):
        """Test MinIOValidationError"""
        error = MinIOValidationError("Validation failed")
        assert str(error) == "Validation failed"
        assert isinstance(error, MinIOError)

    def test_api_error(self):
        """Test MinIOAPIError"""
        error = MinIOAPIError("API failed", 500, "Internal Server Error")
        assert str(error) == "API failed"
        assert error.status_code == 500
        assert error.response_body == "Internal Server Error"
        assert isinstance(error, MinIOError)


if __name__ == "__main__":
    pytest.main([__file__, "-v"])

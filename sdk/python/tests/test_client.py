"""
Unit tests for MinIO Enterprise Python SDK
"""

import pytest
from unittest.mock import Mock, patch
from minio_enterprise import (
    Client,
    MinIOError,
    AuthenticationError,
    QuotaExceededError,
    NotFoundError,
    InvalidRequestError,
)


class TestClient:
    """Test suite for MinIO Client"""

    def test_client_initialization_valid(self):
        """Test client initialization with valid config"""
        client = Client(
            endpoint="http://localhost:9000",
            api_key="test-key",
            api_secret="test-secret",
            tenant_id="test-tenant",
        )
        assert client.endpoint == "http://localhost:9000"
        assert client.api_key == "test-key"
        assert client.tenant_id == "test-tenant"

    def test_client_initialization_missing_endpoint(self):
        """Test client initialization fails without endpoint"""
        with pytest.raises(ValueError, match="endpoint is required"):
            Client(
                endpoint="",
                api_key="test-key",
                api_secret="test-secret",
                tenant_id="test-tenant",
            )

    def test_client_initialization_missing_api_key(self):
        """Test client initialization fails without API key"""
        with pytest.raises(ValueError, match="api_key is required"):
            Client(
                endpoint="http://localhost:9000",
                api_key="",
                api_secret="test-secret",
                tenant_id="test-tenant",
            )

    def test_client_initialization_missing_tenant_id(self):
        """Test client initialization fails without tenant ID"""
        with pytest.raises(ValueError, match="tenant_id is required"):
            Client(
                endpoint="http://localhost:9000",
                api_key="test-key",
                api_secret="test-secret",
                tenant_id="",
            )

    @patch("minio_enterprise.client.requests.Session")
    def test_upload_success(self, mock_session_class):
        """Test successful upload"""
        mock_session = Mock()
        mock_response = Mock()
        mock_response.status_code = 200
        mock_session.put.return_value = mock_response
        mock_session_class.return_value = mock_session

        client = Client(
            endpoint="http://localhost:9000",
            api_key="test-key",
            api_secret="test-secret",
            tenant_id="test-tenant",
        )

        client.upload("test-bucket", "test-key", b"test data")

        mock_session.put.assert_called_once()
        args, kwargs = mock_session.put.call_args
        assert "tenant_id=test-tenant" in args[0]
        assert "bucket=test-bucket" in args[0]
        assert kwargs["data"] == b"test data"

    @patch("minio_enterprise.client.requests.Session")
    def test_download_success(self, mock_session_class):
        """Test successful download"""
        mock_session = Mock()
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.content = b"test data"
        mock_session.get.return_value = mock_response
        mock_session_class.return_value = mock_session

        client = Client(
            endpoint="http://localhost:9000",
            api_key="test-key",
            api_secret="test-secret",
            tenant_id="test-tenant",
        )

        data = client.download("test-bucket", "test-key")

        assert data == b"test data"
        mock_session.get.assert_called_once()

    @patch("minio_enterprise.client.requests.Session")
    def test_delete_success(self, mock_session_class):
        """Test successful delete"""
        mock_session = Mock()
        mock_response = Mock()
        mock_response.status_code = 200
        mock_session.delete.return_value = mock_response
        mock_session_class.return_value = mock_session

        client = Client(
            endpoint="http://localhost:9000",
            api_key="test-key",
            api_secret="test-secret",
            tenant_id="test-tenant",
        )

        client.delete("test-bucket", "test-key")

        mock_session.delete.assert_called_once()

    @patch("minio_enterprise.client.requests.Session")
    def test_list_success(self, mock_session_class):
        """Test successful list"""
        mock_session = Mock()
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = [
            {"key": "file1.txt", "size": 100},
            {"key": "file2.txt", "size": 200},
        ]
        mock_session.get.return_value = mock_response
        mock_session_class.return_value = mock_session

        client = Client(
            endpoint="http://localhost:9000",
            api_key="test-key",
            api_secret="test-secret",
            tenant_id="test-tenant",
        )

        objects = client.list("test-bucket")

        assert len(objects) == 2
        assert objects[0]["key"] == "file1.txt"
        assert objects[1]["size"] == 200

    @patch("minio_enterprise.client.requests.Session")
    def test_get_quota_success(self, mock_session_class):
        """Test successful get_quota"""
        mock_session = Mock()
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "tenant_id": "test-tenant",
            "used": 1000,
            "limit": 10000,
            "percentage": 10.0,
        }
        mock_session.get.return_value = mock_response
        mock_session_class.return_value = mock_session

        client = Client(
            endpoint="http://localhost:9000",
            api_key="test-key",
            api_secret="test-secret",
            tenant_id="test-tenant",
        )

        quota = client.get_quota()

        assert quota["used"] == 1000
        assert quota["limit"] == 10000
        assert quota["percentage"] == 10.0

    @patch("minio_enterprise.client.requests.Session")
    def test_health_success(self, mock_session_class):
        """Test successful health check"""
        mock_session = Mock()
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "status": "healthy",
            "timestamp": "2024-01-01T00:00:00Z",
        }
        mock_session.get.return_value = mock_response
        mock_session_class.return_value = mock_session

        client = Client(
            endpoint="http://localhost:9000",
            api_key="test-key",
            api_secret="test-secret",
            tenant_id="test-tenant",
        )

        health = client.health()

        assert health["status"] == "healthy"

    @patch("minio_enterprise.client.requests.Session")
    def test_authentication_error(self, mock_session_class):
        """Test authentication error handling"""
        mock_session = Mock()
        mock_response = Mock()
        mock_response.status_code = 401
        mock_response.text = "Unauthorized"
        mock_session.put.return_value = mock_response
        mock_session_class.return_value = mock_session

        client = Client(
            endpoint="http://localhost:9000",
            api_key="test-key",
            api_secret="test-secret",
            tenant_id="test-tenant",
        )

        with pytest.raises(AuthenticationError):
            client.upload("test-bucket", "test-key", b"test data")

    @patch("minio_enterprise.client.requests.Session")
    def test_quota_exceeded_error(self, mock_session_class):
        """Test quota exceeded error handling"""
        mock_session = Mock()
        mock_response = Mock()
        mock_response.status_code = 403
        mock_response.text = "Quota exceeded"
        mock_session.put.return_value = mock_response
        mock_session_class.return_value = mock_session

        client = Client(
            endpoint="http://localhost:9000",
            api_key="test-key",
            api_secret="test-secret",
            tenant_id="test-tenant",
        )

        with pytest.raises(QuotaExceededError):
            client.upload("test-bucket", "test-key", b"test data")

    @patch("minio_enterprise.client.requests.Session")
    def test_not_found_error(self, mock_session_class):
        """Test not found error handling"""
        mock_session = Mock()
        mock_response = Mock()
        mock_response.status_code = 404
        mock_response.text = "Not found"
        mock_session.get.return_value = mock_response
        mock_session_class.return_value = mock_session

        client = Client(
            endpoint="http://localhost:9000",
            api_key="test-key",
            api_secret="test-secret",
            tenant_id="test-tenant",
        )

        with pytest.raises(NotFoundError):
            client.download("test-bucket", "test-key")

    @patch("minio_enterprise.client.requests.Session")
    def test_invalid_request_error(self, mock_session_class):
        """Test invalid request error handling"""
        mock_session = Mock()
        mock_response = Mock()
        mock_response.status_code = 400
        mock_response.text = "Bad request"
        mock_session.put.return_value = mock_response
        mock_session_class.return_value = mock_session

        client = Client(
            endpoint="http://localhost:9000",
            api_key="test-key",
            api_secret="test-secret",
            tenant_id="test-tenant",
        )

        with pytest.raises(InvalidRequestError):
            client.upload("test-bucket", "test-key", b"test data")

    def test_context_manager(self):
        """Test context manager usage"""
        with Client(
            endpoint="http://localhost:9000",
            api_key="test-key",
            api_secret="test-secret",
            tenant_id="test-tenant",
        ) as client:
            assert client is not None
            assert client.session is not None

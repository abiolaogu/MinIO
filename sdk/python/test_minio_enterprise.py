"""
Unit tests for MinIO Enterprise Python SDK
"""

import io
import json
import unittest
from unittest.mock import Mock, patch, MagicMock
import requests

from minio_enterprise import (
    MinIOClient,
    MinIOError,
    ValidationError,
    APIError,
)


class TestMinIOClient(unittest.TestCase):
    """Test MinIO client"""

    def test_init_requires_endpoint(self):
        """Test that endpoint is required"""
        with self.assertRaises(ValidationError):
            MinIOClient(endpoint="")

    def test_init_with_api_key(self):
        """Test initialization with API key"""
        client = MinIOClient(
            endpoint="http://localhost:9000",
            api_key="test-key",
        )
        self.assertEqual(client.endpoint, "http://localhost:9000")
        self.assertEqual(client.api_key, "test-key")
        self.assertIn("X-API-Key", client.session.headers)

    def test_init_with_token(self):
        """Test initialization with JWT token"""
        client = MinIOClient(
            endpoint="http://localhost:9000",
            token="jwt-token",
        )
        self.assertIn("Authorization", client.session.headers)

    @patch("minio_enterprise.requests.Session.put")
    def test_upload_success(self, mock_put):
        """Test successful upload"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "key": "test.txt",
            "etag": "abc123",
            "size": 11,
        }
        mock_put.return_value = mock_response

        client = MinIOClient(
            endpoint="http://localhost:9000",
            api_key="test-key",
        )

        data = io.BytesIO(b"hello world")
        result = client.upload(
            tenant_id="tenant1",
            key="test.txt",
            data=data,
        )

        self.assertEqual(result["key"], "test.txt")
        self.assertEqual(result["etag"], "abc123")
        self.assertEqual(result["size"], 11)

    def test_upload_validation_errors(self):
        """Test upload validation"""
        client = MinIOClient(
            endpoint="http://localhost:9000",
            api_key="test-key",
        )

        # Missing tenant_id
        with self.assertRaises(ValidationError):
            client.upload(tenant_id="", key="test.txt", data=io.BytesIO(b"test"))

        # Missing key
        with self.assertRaises(ValidationError):
            client.upload(tenant_id="tenant1", key="", data=io.BytesIO(b"test"))

        # Missing data
        with self.assertRaises(ValidationError):
            client.upload(tenant_id="tenant1", key="test.txt", data=None)

    @patch("minio_enterprise.requests.Session.put")
    def test_upload_api_error(self, mock_put):
        """Test upload API error"""
        mock_response = Mock()
        mock_response.status_code = 500
        mock_response.text = "Internal Server Error"
        mock_response.raise_for_status.side_effect = requests.exceptions.HTTPError(
            response=mock_response
        )
        mock_put.return_value = mock_response

        client = MinIOClient(
            endpoint="http://localhost:9000",
            api_key="test-key",
        )

        with self.assertRaises(APIError) as ctx:
            client.upload(
                tenant_id="tenant1",
                key="test.txt",
                data=io.BytesIO(b"test"),
            )
        self.assertEqual(ctx.exception.status_code, 500)

    @patch("minio_enterprise.requests.Session.get")
    def test_download_success(self, mock_get):
        """Test successful download"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.raw = io.BytesIO(b"hello world")
        mock_get.return_value = mock_response

        client = MinIOClient(
            endpoint="http://localhost:9000",
            api_key="test-key",
        )

        stream = client.download(tenant_id="tenant1", key="test.txt")
        data = stream.read()

        self.assertEqual(data, b"hello world")

    def test_download_validation_errors(self):
        """Test download validation"""
        client = MinIOClient(
            endpoint="http://localhost:9000",
            api_key="test-key",
        )

        # Missing tenant_id
        with self.assertRaises(ValidationError):
            client.download(tenant_id="", key="test.txt")

        # Missing key
        with self.assertRaises(ValidationError):
            client.download(tenant_id="tenant1", key="")

    @patch("minio_enterprise.requests.Session.delete")
    def test_delete_success(self, mock_delete):
        """Test successful delete"""
        mock_response = Mock()
        mock_response.status_code = 204
        mock_delete.return_value = mock_response

        client = MinIOClient(
            endpoint="http://localhost:9000",
            api_key="test-key",
        )

        # Should not raise
        client.delete(tenant_id="tenant1", key="test.txt")

    def test_delete_validation_errors(self):
        """Test delete validation"""
        client = MinIOClient(
            endpoint="http://localhost:9000",
            api_key="test-key",
        )

        # Missing tenant_id
        with self.assertRaises(ValidationError):
            client.delete(tenant_id="", key="test.txt")

        # Missing key
        with self.assertRaises(ValidationError):
            client.delete(tenant_id="tenant1", key="")

    @patch("minio_enterprise.requests.Session.get")
    def test_list_success(self, mock_get):
        """Test successful list"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "objects": [
                {"key": "file1.txt", "size": 100},
                {"key": "file2.txt", "size": 200},
            ],
            "is_truncated": False,
        }
        mock_get.return_value = mock_response

        client = MinIOClient(
            endpoint="http://localhost:9000",
            api_key="test-key",
        )

        result = client.list(tenant_id="tenant1", prefix="file")

        self.assertEqual(len(result["objects"]), 2)
        self.assertFalse(result["is_truncated"])

    def test_list_validation_errors(self):
        """Test list validation"""
        client = MinIOClient(
            endpoint="http://localhost:9000",
            api_key="test-key",
        )

        # Missing tenant_id
        with self.assertRaises(ValidationError):
            client.list(tenant_id="")

    @patch("minio_enterprise.requests.Session.get")
    def test_list_all_pagination(self, mock_get):
        """Test list_all with pagination"""
        # Mock two pages
        mock_response1 = Mock()
        mock_response1.status_code = 200
        mock_response1.json.return_value = {
            "objects": [
                {"key": "file1.txt", "size": 100},
                {"key": "file2.txt", "size": 200},
            ],
            "is_truncated": True,
            "next_marker": "marker123",
        }

        mock_response2 = Mock()
        mock_response2.status_code = 200
        mock_response2.json.return_value = {
            "objects": [
                {"key": "file3.txt", "size": 300},
            ],
            "is_truncated": False,
        }

        mock_get.side_effect = [mock_response1, mock_response2]

        client = MinIOClient(
            endpoint="http://localhost:9000",
            api_key="test-key",
        )

        objects = list(client.list_all(tenant_id="tenant1"))

        self.assertEqual(len(objects), 3)
        self.assertEqual(objects[0]["key"], "file1.txt")
        self.assertEqual(objects[2]["key"], "file3.txt")

    @patch("minio_enterprise.requests.Session.get")
    def test_get_quota_success(self, mock_get):
        """Test successful get quota"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "tenant_id": "tenant1",
            "used": 1000,
            "limit": 10000,
            "objects": 5,
        }
        mock_get.return_value = mock_response

        client = MinIOClient(
            endpoint="http://localhost:9000",
            api_key="test-key",
        )

        quota = client.get_quota(tenant_id="tenant1")

        self.assertEqual(quota["tenant_id"], "tenant1")
        self.assertEqual(quota["used"], 1000)
        self.assertEqual(quota["limit"], 10000)
        self.assertEqual(quota["objects"], 5)

    def test_get_quota_validation_errors(self):
        """Test get quota validation"""
        client = MinIOClient(
            endpoint="http://localhost:9000",
            api_key="test-key",
        )

        # Missing tenant_id
        with self.assertRaises(ValidationError):
            client.get_quota(tenant_id="")

    @patch("minio_enterprise.requests.Session.get")
    def test_health_success(self, mock_get):
        """Test successful health check"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "status": "healthy",
            "version": "2.0.0",
            "uptime": 3600,
            "checks": {"database": "ok", "cache": "ok"},
        }
        mock_get.return_value = mock_response

        client = MinIOClient(
            endpoint="http://localhost:9000",
            api_key="test-key",
        )

        health = client.health()

        self.assertEqual(health["status"], "healthy")
        self.assertEqual(health["version"], "2.0.0")

    def test_context_manager(self):
        """Test context manager usage"""
        with MinIOClient(
            endpoint="http://localhost:9000",
            api_key="test-key",
        ) as client:
            self.assertIsNotNone(client.session)

        # Session should be closed after context
        # Note: We can't easily test this without mocking


if __name__ == "__main__":
    unittest.main()

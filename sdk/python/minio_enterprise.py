"""
MinIO Enterprise Python SDK

Official Python SDK for MinIO Enterprise - Ultra-High-Performance Object Storage
"""

import json
import time
from typing import Dict, Optional, BinaryIO, Iterator, Any
from urllib.parse import urlencode
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry


__version__ = "2.0.0"


class MinIOError(Exception):
    """Base exception for MinIO SDK errors"""
    pass


class ValidationError(MinIOError):
    """Raised when request validation fails"""
    pass


class APIError(MinIOError):
    """Raised when API request fails"""
    def __init__(self, message: str, status_code: int = None):
        super().__init__(message)
        self.status_code = status_code


class MinIOClient:
    """MinIO Enterprise client"""

    def __init__(
        self,
        endpoint: str,
        api_key: Optional[str] = None,
        token: Optional[str] = None,
        timeout: int = 30,
        retry_max: int = 3,
        retry_backoff: float = 1.0,
        verify_ssl: bool = True,
    ):
        """
        Initialize MinIO Enterprise client

        Args:
            endpoint: MinIO API endpoint (e.g., "http://localhost:9000")
            api_key: API key for authentication
            token: JWT token for authentication
            timeout: Request timeout in seconds (default: 30)
            retry_max: Maximum retry attempts (default: 3)
            retry_backoff: Backoff factor for retries (default: 1.0)
            verify_ssl: Verify SSL certificates (default: True)
        """
        if not endpoint:
            raise ValidationError("endpoint is required")

        self.endpoint = endpoint.rstrip("/")
        self.api_key = api_key
        self.token = token
        self.timeout = timeout
        self.verify_ssl = verify_ssl

        # Create session with connection pooling
        self.session = requests.Session()

        # Configure retry strategy
        retry_strategy = Retry(
            total=retry_max,
            backoff_factor=retry_backoff,
            status_forcelist=[500, 502, 503, 504],
            allowed_methods=["GET", "PUT", "DELETE", "POST"],
        )
        adapter = HTTPAdapter(
            max_retries=retry_strategy,
            pool_connections=100,
            pool_maxsize=100,
        )
        self.session.mount("http://", adapter)
        self.session.mount("https://", adapter)

        # Set default headers
        if self.token:
            self.session.headers.update({"Authorization": f"Bearer {self.token}"})
        elif self.api_key:
            self.session.headers.update({"X-API-Key": self.api_key})

    def upload(
        self,
        tenant_id: str,
        key: str,
        data: BinaryIO,
        size: Optional[int] = None,
        content_type: Optional[str] = None,
        metadata: Optional[Dict[str, str]] = None,
    ) -> Dict[str, Any]:
        """
        Upload an object to MinIO

        Args:
            tenant_id: Tenant identifier
            key: Object key/path
            data: Binary data to upload
            size: Size of data in bytes (optional)
            content_type: Content type of the object (optional)
            metadata: Custom metadata dictionary (optional)

        Returns:
            Dict with upload response containing 'key', 'etag', and 'size'

        Raises:
            ValidationError: If required parameters are missing
            APIError: If the API request fails
        """
        if not tenant_id:
            raise ValidationError("tenant_id is required")
        if not key:
            raise ValidationError("key is required")
        if data is None:
            raise ValidationError("data is required")

        url = f"{self.endpoint}/upload"
        params = {"tenant": tenant_id, "key": key}

        headers = {}
        if content_type:
            headers["Content-Type"] = content_type

        try:
            response = self.session.put(
                url,
                params=params,
                data=data,
                headers=headers,
                timeout=self.timeout,
                verify=self.verify_ssl,
            )
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError as e:
            raise APIError(
                f"Upload failed: {e.response.text}",
                status_code=e.response.status_code,
            )
        except requests.exceptions.RequestException as e:
            raise APIError(f"Upload request failed: {str(e)}")

    def download(self, tenant_id: str, key: str) -> BinaryIO:
        """
        Download an object from MinIO

        Args:
            tenant_id: Tenant identifier
            key: Object key/path

        Returns:
            Binary stream of the object data

        Raises:
            ValidationError: If required parameters are missing
            APIError: If the API request fails
        """
        if not tenant_id:
            raise ValidationError("tenant_id is required")
        if not key:
            raise ValidationError("key is required")

        url = f"{self.endpoint}/download"
        params = {"tenant": tenant_id, "key": key}

        try:
            response = self.session.get(
                url,
                params=params,
                timeout=self.timeout,
                verify=self.verify_ssl,
                stream=True,
            )
            response.raise_for_status()
            response.raw.decode_content = True
            return response.raw
        except requests.exceptions.HTTPError as e:
            raise APIError(
                f"Download failed: {e.response.text}",
                status_code=e.response.status_code,
            )
        except requests.exceptions.RequestException as e:
            raise APIError(f"Download request failed: {str(e)}")

    def delete(self, tenant_id: str, key: str) -> None:
        """
        Delete an object from MinIO

        Args:
            tenant_id: Tenant identifier
            key: Object key/path

        Raises:
            ValidationError: If required parameters are missing
            APIError: If the API request fails
        """
        if not tenant_id:
            raise ValidationError("tenant_id is required")
        if not key:
            raise ValidationError("key is required")

        url = f"{self.endpoint}/delete"
        params = {"tenant": tenant_id, "key": key}

        try:
            response = self.session.delete(
                url,
                params=params,
                timeout=self.timeout,
                verify=self.verify_ssl,
            )
            response.raise_for_status()
        except requests.exceptions.HTTPError as e:
            raise APIError(
                f"Delete failed: {e.response.text}",
                status_code=e.response.status_code,
            )
        except requests.exceptions.RequestException as e:
            raise APIError(f"Delete request failed: {str(e)}")

    def list(
        self,
        tenant_id: str,
        prefix: Optional[str] = None,
        limit: Optional[int] = None,
        marker: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        List objects in MinIO

        Args:
            tenant_id: Tenant identifier
            prefix: Filter objects by prefix (optional)
            limit: Maximum number of objects to return (optional)
            marker: Pagination marker for next page (optional)

        Returns:
            Dict with 'objects', 'is_truncated', and 'next_marker' keys

        Raises:
            ValidationError: If required parameters are missing
            APIError: If the API request fails
        """
        if not tenant_id:
            raise ValidationError("tenant_id is required")

        url = f"{self.endpoint}/list"
        params = {"tenant": tenant_id}

        if prefix:
            params["prefix"] = prefix
        if limit:
            params["limit"] = limit
        if marker:
            params["marker"] = marker

        try:
            response = self.session.get(
                url,
                params=params,
                timeout=self.timeout,
                verify=self.verify_ssl,
            )
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError as e:
            raise APIError(
                f"List failed: {e.response.text}",
                status_code=e.response.status_code,
            )
        except requests.exceptions.RequestException as e:
            raise APIError(f"List request failed: {str(e)}")

    def list_all(
        self,
        tenant_id: str,
        prefix: Optional[str] = None,
    ) -> Iterator[Dict[str, Any]]:
        """
        List all objects with automatic pagination

        Args:
            tenant_id: Tenant identifier
            prefix: Filter objects by prefix (optional)

        Yields:
            Object dictionaries

        Raises:
            ValidationError: If required parameters are missing
            APIError: If the API request fails
        """
        marker = None
        while True:
            response = self.list(
                tenant_id=tenant_id,
                prefix=prefix,
                marker=marker,
            )

            for obj in response.get("objects", []):
                yield obj

            if not response.get("is_truncated", False):
                break

            marker = response.get("next_marker")

    def get_quota(self, tenant_id: str) -> Dict[str, Any]:
        """
        Get tenant quota information

        Args:
            tenant_id: Tenant identifier

        Returns:
            Dict with 'tenant_id', 'used', 'limit', and 'objects' keys

        Raises:
            ValidationError: If required parameters are missing
            APIError: If the API request fails
        """
        if not tenant_id:
            raise ValidationError("tenant_id is required")

        url = f"{self.endpoint}/quota"
        params = {"tenant": tenant_id}

        try:
            response = self.session.get(
                url,
                params=params,
                timeout=self.timeout,
                verify=self.verify_ssl,
            )
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError as e:
            raise APIError(
                f"Get quota failed: {e.response.text}",
                status_code=e.response.status_code,
            )
        except requests.exceptions.RequestException as e:
            raise APIError(f"Get quota request failed: {str(e)}")

    def health(self) -> Dict[str, Any]:
        """
        Check service health

        Returns:
            Dict with 'status', 'version', 'uptime', and 'checks' keys

        Raises:
            APIError: If the API request fails
        """
        url = f"{self.endpoint}/health"

        try:
            response = self.session.get(
                url,
                timeout=self.timeout,
                verify=self.verify_ssl,
            )
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError as e:
            raise APIError(
                f"Health check failed: {e.response.text}",
                status_code=e.response.status_code,
            )
        except requests.exceptions.RequestException as e:
            raise APIError(f"Health check request failed: {str(e)}")

    def close(self) -> None:
        """Close the client and release resources"""
        self.session.close()

    def __enter__(self):
        """Context manager entry"""
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit"""
        self.close()

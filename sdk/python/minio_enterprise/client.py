"""MinIO Enterprise Python SDK Client"""

import json
import time
from typing import Optional, Dict, Any, List, IO
from urllib.parse import urlencode
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry


class MinIOError(Exception):
    """Base exception for MinIO SDK errors"""
    pass


class MinIOConnectionError(MinIOError):
    """Connection error exception"""
    pass


class MinIOValidationError(MinIOError):
    """Validation error exception"""
    pass


class MinIOAPIError(MinIOError):
    """API error exception"""
    def __init__(self, message: str, status_code: int, response_body: str):
        super().__init__(message)
        self.status_code = status_code
        self.response_body = response_body


class Config:
    """Configuration for MinIO Enterprise Client"""

    def __init__(
        self,
        base_url: str,
        api_key: Optional[str] = None,
        timeout: int = 30,
        max_retries: int = 3,
    ):
        """Initialize client configuration

        Args:
            base_url: MinIO API base URL (e.g., "http://localhost:9000")
            api_key: API key for authentication
            timeout: Request timeout in seconds (default: 30)
            max_retries: Maximum retry attempts (default: 3)
        """
        if not base_url:
            raise MinIOValidationError("base_url is required")

        self.base_url = base_url.rstrip('/')
        self.api_key = api_key
        self.timeout = timeout
        self.max_retries = max_retries


class UploadRequest:
    """Upload request parameters"""

    def __init__(self, tenant_id: str, object_id: str, data: bytes):
        """Initialize upload request

        Args:
            tenant_id: Tenant identifier
            object_id: Object/file identifier
            data: File data as bytes
        """
        if not tenant_id:
            raise MinIOValidationError("tenant_id is required")
        if not object_id:
            raise MinIOValidationError("object_id is required")

        self.tenant_id = tenant_id
        self.object_id = object_id
        self.data = data


class DownloadRequest:
    """Download request parameters"""

    def __init__(self, tenant_id: str, object_id: str):
        """Initialize download request

        Args:
            tenant_id: Tenant identifier
            object_id: Object/file identifier
        """
        if not tenant_id:
            raise MinIOValidationError("tenant_id is required")
        if not object_id:
            raise MinIOValidationError("object_id is required")

        self.tenant_id = tenant_id
        self.object_id = object_id


class DeleteRequest:
    """Delete request parameters"""

    def __init__(self, tenant_id: str, object_id: str):
        """Initialize delete request

        Args:
            tenant_id: Tenant identifier
            object_id: Object/file identifier
        """
        if not tenant_id:
            raise MinIOValidationError("tenant_id is required")
        if not object_id:
            raise MinIOValidationError("object_id is required")

        self.tenant_id = tenant_id
        self.object_id = object_id


class ListRequest:
    """List request parameters"""

    def __init__(
        self,
        tenant_id: str,
        prefix: Optional[str] = None,
        limit: int = 100,
    ):
        """Initialize list request

        Args:
            tenant_id: Tenant identifier
            prefix: Optional prefix filter
            limit: Optional limit (default: 100)
        """
        if not tenant_id:
            raise MinIOValidationError("tenant_id is required")

        self.tenant_id = tenant_id
        self.prefix = prefix
        self.limit = limit


class QuotaRequest:
    """Quota request parameters"""

    def __init__(self, tenant_id: str):
        """Initialize quota request

        Args:
            tenant_id: Tenant identifier
        """
        if not tenant_id:
            raise MinIOValidationError("tenant_id is required")

        self.tenant_id = tenant_id


class Client:
    """MinIO Enterprise SDK Client"""

    def __init__(self, config: Config):
        """Initialize MinIO client

        Args:
            config: Client configuration
        """
        self.config = config
        self.session = self._create_session()

    def _create_session(self) -> requests.Session:
        """Create HTTP session with connection pooling and retry logic"""
        session = requests.Session()

        # Configure retry strategy
        retry_strategy = Retry(
            total=self.config.max_retries,
            backoff_factor=1,
            status_forcelist=[429, 500, 502, 503, 504],
            allowed_methods=["HEAD", "GET", "PUT", "DELETE", "OPTIONS", "TRACE"]
        )

        adapter = HTTPAdapter(
            max_retries=retry_strategy,
            pool_connections=100,
            pool_maxsize=100,
        )

        session.mount("http://", adapter)
        session.mount("https://", adapter)

        # Set default headers
        session.headers.update({
            "Content-Type": "application/json",
            "User-Agent": "minio-enterprise-python-sdk/1.0.0",
        })

        if self.config.api_key:
            session.headers.update({
                "Authorization": f"Bearer {self.config.api_key}"
            })

        return session

    def upload(self, request: UploadRequest) -> Dict[str, Any]:
        """Upload a file to MinIO Enterprise

        Args:
            request: Upload request parameters

        Returns:
            Upload response dictionary

        Raises:
            MinIOError: If upload fails
        """
        url = f"{self.config.base_url}/upload"

        payload = {
            "tenant_id": request.tenant_id,
            "object_id": request.object_id,
            "data": request.data.decode('utf-8') if isinstance(request.data, bytes) else request.data,
        }

        try:
            response = self.session.put(
                url,
                json=payload,
                timeout=self.config.timeout,
            )

            if response.status_code >= 400:
                raise MinIOAPIError(
                    f"Upload failed with status {response.status_code}",
                    response.status_code,
                    response.text,
                )

            return response.json()

        except requests.exceptions.ConnectionError as e:
            raise MinIOConnectionError(f"Connection failed: {e}")
        except requests.exceptions.Timeout as e:
            raise MinIOConnectionError(f"Request timeout: {e}")
        except requests.exceptions.RequestException as e:
            raise MinIOError(f"Upload failed: {e}")

    def download(self, request: DownloadRequest) -> Dict[str, Any]:
        """Download a file from MinIO Enterprise

        Args:
            request: Download request parameters

        Returns:
            Download response dictionary with 'data' key containing file bytes

        Raises:
            MinIOError: If download fails
        """
        url = f"{self.config.base_url}/download"
        params = {
            "tenant_id": request.tenant_id,
            "object_id": request.object_id,
        }

        try:
            response = self.session.get(
                url,
                params=params,
                timeout=self.config.timeout,
            )

            if response.status_code >= 400:
                raise MinIOAPIError(
                    f"Download failed with status {response.status_code}",
                    response.status_code,
                    response.text,
                )

            result = response.json()
            result['data'] = response.content
            return result

        except requests.exceptions.ConnectionError as e:
            raise MinIOConnectionError(f"Connection failed: {e}")
        except requests.exceptions.Timeout as e:
            raise MinIOConnectionError(f"Request timeout: {e}")
        except requests.exceptions.RequestException as e:
            raise MinIOError(f"Download failed: {e}")

    def delete(self, request: DeleteRequest) -> Dict[str, Any]:
        """Delete a file from MinIO Enterprise

        Args:
            request: Delete request parameters

        Returns:
            Delete response dictionary

        Raises:
            MinIOError: If deletion fails
        """
        url = f"{self.config.base_url}/delete"
        params = {
            "tenant_id": request.tenant_id,
            "object_id": request.object_id,
        }

        try:
            response = self.session.delete(
                url,
                params=params,
                timeout=self.config.timeout,
            )

            if response.status_code >= 400:
                raise MinIOAPIError(
                    f"Delete failed with status {response.status_code}",
                    response.status_code,
                    response.text,
                )

            return response.json()

        except requests.exceptions.ConnectionError as e:
            raise MinIOConnectionError(f"Connection failed: {e}")
        except requests.exceptions.Timeout as e:
            raise MinIOConnectionError(f"Request timeout: {e}")
        except requests.exceptions.RequestException as e:
            raise MinIOError(f"Delete failed: {e}")

    def list(self, request: ListRequest) -> Dict[str, Any]:
        """List objects in MinIO Enterprise

        Args:
            request: List request parameters

        Returns:
            List response dictionary with 'objects' key containing object list

        Raises:
            MinIOError: If list operation fails
        """
        url = f"{self.config.base_url}/list"
        params = {
            "tenant_id": request.tenant_id,
            "limit": request.limit,
        }

        if request.prefix:
            params["prefix"] = request.prefix

        try:
            response = self.session.get(
                url,
                params=params,
                timeout=self.config.timeout,
            )

            if response.status_code >= 400:
                raise MinIOAPIError(
                    f"List failed with status {response.status_code}",
                    response.status_code,
                    response.text,
                )

            return response.json()

        except requests.exceptions.ConnectionError as e:
            raise MinIOConnectionError(f"Connection failed: {e}")
        except requests.exceptions.Timeout as e:
            raise MinIOConnectionError(f"Request timeout: {e}")
        except requests.exceptions.RequestException as e:
            raise MinIOError(f"List failed: {e}")

    def get_quota(self, request: QuotaRequest) -> Dict[str, Any]:
        """Get quota information for a tenant

        Args:
            request: Quota request parameters

        Returns:
            Quota response dictionary

        Raises:
            MinIOError: If quota request fails
        """
        url = f"{self.config.base_url}/quota"
        params = {
            "tenant_id": request.tenant_id,
        }

        try:
            response = self.session.get(
                url,
                params=params,
                timeout=self.config.timeout,
            )

            if response.status_code >= 400:
                raise MinIOAPIError(
                    f"Get quota failed with status {response.status_code}",
                    response.status_code,
                    response.text,
                )

            return response.json()

        except requests.exceptions.ConnectionError as e:
            raise MinIOConnectionError(f"Connection failed: {e}")
        except requests.exceptions.Timeout as e:
            raise MinIOConnectionError(f"Request timeout: {e}")
        except requests.exceptions.RequestException as e:
            raise MinIOError(f"Get quota failed: {e}")

    def health_check(self) -> Dict[str, Any]:
        """Perform a health check on the MinIO service

        Returns:
            Health check response dictionary

        Raises:
            MinIOError: If health check fails
        """
        url = f"{self.config.base_url}/health"

        try:
            response = self.session.get(
                url,
                timeout=self.config.timeout,
            )

            if response.status_code >= 400:
                raise MinIOAPIError(
                    f"Health check failed with status {response.status_code}",
                    response.status_code,
                    response.text,
                )

            return response.json()

        except requests.exceptions.ConnectionError as e:
            raise MinIOConnectionError(f"Connection failed: {e}")
        except requests.exceptions.Timeout as e:
            raise MinIOConnectionError(f"Request timeout: {e}")
        except requests.exceptions.RequestException as e:
            raise MinIOError(f"Health check failed: {e}")

    def close(self):
        """Close the HTTP session"""
        self.session.close()

    def __enter__(self):
        """Context manager entry"""
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit"""
        self.close()

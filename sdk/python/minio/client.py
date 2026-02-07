"""MinIO Enterprise Python SDK Client"""

import time
from dataclasses import dataclass
from typing import BinaryIO, Dict, Optional
from urllib.parse import quote, urljoin

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

from .exceptions import (
    AuthenticationError,
    MinIOError,
    NotFoundError,
    QuotaExceededError,
    RateLimitError,
    ServerError,
    ValidationError,
)
from .models import HealthStatus, ListResponse, Object, QuotaInfo


@dataclass
class Config:
    """Configuration for MinIO client"""

    endpoint: str
    api_key: str
    timeout: int = 30
    max_retries: int = 3
    backoff_factor: float = 1.0
    verify_ssl: bool = True


@dataclass
class UploadOptions:
    """Options for upload operation"""

    content_type: Optional[str] = None
    metadata: Optional[Dict[str, str]] = None


@dataclass
class ListOptions:
    """Options for list operation"""

    prefix: Optional[str] = None
    max_keys: Optional[int] = None


class Client:
    """MinIO Enterprise Python SDK Client"""

    def __init__(self, config: Config):
        """Initialize MinIO client

        Args:
            config: Client configuration

        Raises:
            ValidationError: If configuration is invalid
        """
        if not config.endpoint:
            raise ValidationError("endpoint is required")

        if not config.api_key:
            raise ValidationError("API key is required")

        self.endpoint = config.endpoint.rstrip("/")
        self.api_key = config.api_key
        self.timeout = config.timeout

        # Configure session with retry logic
        self.session = requests.Session()

        # Configure retry strategy
        retry_strategy = Retry(
            total=config.max_retries,
            backoff_factor=config.backoff_factor,
            status_forcelist=[429, 500, 502, 503, 504],
            allowed_methods=["HEAD", "GET", "PUT", "DELETE", "OPTIONS", "TRACE"],
        )

        adapter = HTTPAdapter(
            max_retries=retry_strategy,
            pool_connections=100,
            pool_maxsize=10,
        )

        self.session.mount("http://", adapter)
        self.session.mount("https://", adapter)

        # Set default headers
        self.session.headers.update(
            {
                "Authorization": f"Bearer {self.api_key}",
                "User-Agent": "MinIO-Python-SDK/1.0.0",
            }
        )

        self.verify_ssl = config.verify_ssl

    def upload(
        self,
        tenant_id: str,
        key: str,
        data: BinaryIO,
        options: Optional[UploadOptions] = None,
    ) -> None:
        """Upload an object to MinIO

        Args:
            tenant_id: Tenant identifier
            key: Object key/path
            data: File-like object containing data to upload
            options: Upload options

        Raises:
            ValidationError: If parameters are invalid
            QuotaExceededError: If tenant quota is exceeded
            MinIOError: If upload fails
        """
        if not tenant_id:
            raise ValidationError("tenant_id is required")

        if not key:
            raise ValidationError("key is required")

        if data is None:
            raise ValidationError("data is required")

        if options is None:
            options = UploadOptions()

        url = f"{self.endpoint}/upload?tenant_id={quote(tenant_id)}&key={quote(key)}"

        headers = {}
        if options.content_type:
            headers["Content-Type"] = options.content_type
        else:
            headers["Content-Type"] = "application/octet-stream"

        try:
            response = self.session.put(
                url, data=data, headers=headers, timeout=self.timeout, verify=self.verify_ssl
            )
            self._handle_response(response)
        except requests.RequestException as e:
            raise MinIOError(f"Upload failed: {str(e)}")

    def download(self, tenant_id: str, key: str) -> bytes:
        """Download an object from MinIO

        Args:
            tenant_id: Tenant identifier
            key: Object key/path

        Returns:
            Object data as bytes

        Raises:
            ValidationError: If parameters are invalid
            NotFoundError: If object not found
            MinIOError: If download fails
        """
        if not tenant_id:
            raise ValidationError("tenant_id is required")

        if not key:
            raise ValidationError("key is required")

        url = f"{self.endpoint}/download?tenant_id={quote(tenant_id)}&key={quote(key)}"

        try:
            response = self.session.get(url, timeout=self.timeout, verify=self.verify_ssl)
            self._handle_response(response)
            return response.content
        except requests.RequestException as e:
            raise MinIOError(f"Download failed: {str(e)}")

    def delete(self, tenant_id: str, key: str) -> None:
        """Delete an object from MinIO

        Args:
            tenant_id: Tenant identifier
            key: Object key/path

        Raises:
            ValidationError: If parameters are invalid
            MinIOError: If delete fails
        """
        if not tenant_id:
            raise ValidationError("tenant_id is required")

        if not key:
            raise ValidationError("key is required")

        url = f"{self.endpoint}/delete?tenant_id={quote(tenant_id)}&key={quote(key)}"

        try:
            response = self.session.delete(url, timeout=self.timeout, verify=self.verify_ssl)
            self._handle_response(response)
        except requests.RequestException as e:
            raise MinIOError(f"Delete failed: {str(e)}")

    def list(self, tenant_id: str, options: Optional[ListOptions] = None) -> ListResponse:
        """List objects in tenant storage

        Args:
            tenant_id: Tenant identifier
            options: List options

        Returns:
            ListResponse containing objects

        Raises:
            ValidationError: If parameters are invalid
            MinIOError: If list fails
        """
        if not tenant_id:
            raise ValidationError("tenant_id is required")

        if options is None:
            options = ListOptions()

        url = f"{self.endpoint}/list?tenant_id={quote(tenant_id)}"

        if options.prefix:
            url += f"&prefix={quote(options.prefix)}"

        if options.max_keys:
            url += f"&max_keys={options.max_keys}"

        try:
            response = self.session.get(url, timeout=self.timeout, verify=self.verify_ssl)
            self._handle_response(response)
            return ListResponse.from_dict(response.json())
        except requests.RequestException as e:
            raise MinIOError(f"List failed: {str(e)}")

    def get_quota(self, tenant_id: str) -> QuotaInfo:
        """Get quota information for tenant

        Args:
            tenant_id: Tenant identifier

        Returns:
            QuotaInfo object

        Raises:
            ValidationError: If parameters are invalid
            MinIOError: If request fails
        """
        if not tenant_id:
            raise ValidationError("tenant_id is required")

        url = f"{self.endpoint}/quota?tenant_id={quote(tenant_id)}"

        try:
            response = self.session.get(url, timeout=self.timeout, verify=self.verify_ssl)
            self._handle_response(response)
            return QuotaInfo.from_dict(response.json())
        except requests.RequestException as e:
            raise MinIOError(f"GetQuota failed: {str(e)}")

    def health(self) -> HealthStatus:
        """Check service health

        Returns:
            HealthStatus object

        Raises:
            MinIOError: If health check fails
        """
        url = f"{self.endpoint}/health"

        try:
            response = self.session.get(url, timeout=self.timeout, verify=self.verify_ssl)
            self._handle_response(response)
            return HealthStatus.from_dict(response.json())
        except requests.RequestException as e:
            raise MinIOError(f"Health check failed: {str(e)}")

    def close(self) -> None:
        """Close the client and release resources"""
        self.session.close()

    def __enter__(self):
        """Context manager entry"""
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit"""
        self.close()

    def _handle_response(self, response: requests.Response) -> None:
        """Handle HTTP response and raise appropriate exceptions

        Args:
            response: HTTP response object

        Raises:
            AuthenticationError: If authentication fails (401, 403)
            QuotaExceededError: If quota exceeded
            NotFoundError: If resource not found (404)
            RateLimitError: If rate limited (429)
            ServerError: If server error (5xx)
            MinIOError: For other errors
        """
        if response.status_code < 300:
            return  # Success

        error_body = response.text

        if response.status_code in (401, 403):
            raise AuthenticationError(
                f"Authentication failed: {error_body}",
                status_code=response.status_code,
                response_body=error_body,
            )

        if response.status_code == 404:
            raise NotFoundError(
                f"Resource not found: {error_body}",
                status_code=response.status_code,
                response_body=error_body,
            )

        if response.status_code == 429:
            raise RateLimitError(
                f"Rate limit exceeded: {error_body}",
                status_code=response.status_code,
                response_body=error_body,
            )

        if "quota exceeded" in error_body.lower():
            raise QuotaExceededError(
                f"Quota exceeded: {error_body}",
                status_code=response.status_code,
                response_body=error_body,
            )

        if response.status_code >= 500:
            raise ServerError(
                f"Server error: {error_body}",
                status_code=response.status_code,
                response_body=error_body,
            )

        raise MinIOError(
            f"Request failed with status {response.status_code}: {error_body}",
            status_code=response.status_code,
            response_body=error_body,
        )

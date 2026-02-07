"""
MinIO Enterprise Python Client
"""

import time
from typing import Dict, List, Optional, Any
from urllib.parse import urlencode, quote
import requests

from .exceptions import (
    MinIOError,
    AuthenticationError,
    QuotaExceededError,
    NotFoundError,
    InvalidRequestError,
    ServerError,
)


class Client:
    """
    MinIO Enterprise SDK Client

    Args:
        endpoint: MinIO server endpoint (e.g., "http://localhost:9000")
        api_key: API key for authentication
        api_secret: API secret for authentication
        tenant_id: Tenant ID for multi-tenancy support
        timeout: Request timeout in seconds (default: 30)
        max_retries: Maximum number of retry attempts (default: 3)
        retry_backoff: Initial backoff duration in seconds (default: 0.1)
    """

    def __init__(
        self,
        endpoint: str,
        api_key: str,
        api_secret: str,
        tenant_id: str,
        timeout: int = 30,
        max_retries: int = 3,
        retry_backoff: float = 0.1,
    ):
        if not endpoint:
            raise ValueError("endpoint is required")
        if not api_key:
            raise ValueError("api_key is required")
        if not tenant_id:
            raise ValueError("tenant_id is required")

        self.endpoint = endpoint.rstrip("/")
        self.api_key = api_key
        self.api_secret = api_secret
        self.tenant_id = tenant_id
        self.timeout = timeout
        self.max_retries = max_retries
        self.retry_backoff = retry_backoff

        # Create session for connection pooling
        self.session = requests.Session()
        self.session.headers.update(self._get_auth_headers())

    def _get_auth_headers(self) -> Dict[str, str]:
        """Get authentication headers"""
        return {
            "X-API-Key": self.api_key,
            "X-API-Secret": self.api_secret,
            "X-Tenant-ID": self.tenant_id,
        }

    def _retry_request(self, func, *args, **kwargs) -> Any:
        """Execute a request with exponential backoff retry"""
        last_error = None
        backoff = self.retry_backoff

        for attempt in range(self.max_retries + 1):
            if attempt > 0:
                time.sleep(backoff)
                backoff *= 2  # Exponential backoff

            try:
                return func(*args, **kwargs)
            except ServerError as e:
                last_error = e
                if attempt == self.max_retries:
                    break
                continue
            except MinIOError:
                # Don't retry client errors (4xx)
                raise

        raise MinIOError(
            f"Operation failed after {self.max_retries + 1} attempts: {last_error}"
        )

    def _handle_response(self, response: requests.Response) -> None:
        """Handle HTTP response and raise appropriate exceptions"""
        if response.status_code == 200:
            return

        error_message = response.text or f"Request failed with status {response.status_code}"

        if response.status_code == 401:
            raise AuthenticationError(error_message, response.status_code)
        elif response.status_code == 403:
            if "quota" in error_message.lower():
                raise QuotaExceededError(error_message, response.status_code)
            raise AuthenticationError(error_message, response.status_code)
        elif response.status_code == 404:
            raise NotFoundError(error_message, response.status_code)
        elif response.status_code == 400:
            raise InvalidRequestError(error_message, response.status_code)
        elif response.status_code >= 500:
            raise ServerError(error_message, response.status_code)
        else:
            raise MinIOError(error_message, response.status_code)

    def upload(self, bucket: str, key: str, data: bytes) -> None:
        """
        Upload an object to MinIO

        Args:
            bucket: Bucket name
            key: Object key
            data: Object data as bytes

        Raises:
            QuotaExceededError: If tenant quota is exceeded
            InvalidRequestError: If request parameters are invalid
            MinIOError: For other errors
        """
        params = {
            "tenant_id": self.tenant_id,
            "bucket": bucket,
            "key": key,
        }
        url = f"{self.endpoint}/upload?{urlencode(params)}"

        def _upload():
            response = self.session.put(
                url,
                data=data,
                headers={"Content-Type": "application/octet-stream"},
                timeout=self.timeout,
            )
            self._handle_response(response)

        self._retry_request(_upload)

    def download(self, bucket: str, key: str) -> bytes:
        """
        Download an object from MinIO

        Args:
            bucket: Bucket name
            key: Object key

        Returns:
            Object data as bytes

        Raises:
            NotFoundError: If object is not found
            MinIOError: For other errors
        """
        params = {
            "tenant_id": self.tenant_id,
            "bucket": bucket,
            "key": key,
        }
        url = f"{self.endpoint}/download?{urlencode(params)}"

        def _download():
            response = self.session.get(url, timeout=self.timeout)
            self._handle_response(response)
            return response.content

        return self._retry_request(_download)

    def delete(self, bucket: str, key: str) -> None:
        """
        Delete an object from MinIO

        Args:
            bucket: Bucket name
            key: Object key

        Raises:
            NotFoundError: If object is not found
            MinIOError: For other errors
        """
        params = {
            "tenant_id": self.tenant_id,
            "bucket": bucket,
            "key": key,
        }
        url = f"{self.endpoint}/delete?{urlencode(params)}"

        def _delete():
            response = self.session.delete(url, timeout=self.timeout)
            self._handle_response(response)

        self._retry_request(_delete)

    def list(self, bucket: str, prefix: Optional[str] = None) -> List[Dict[str, Any]]:
        """
        List objects in a bucket

        Args:
            bucket: Bucket name
            prefix: Optional prefix to filter objects

        Returns:
            List of object dictionaries with keys: key, size, last_modified, etag

        Raises:
            MinIOError: For errors
        """
        params = {
            "tenant_id": self.tenant_id,
            "bucket": bucket,
        }
        if prefix:
            params["prefix"] = prefix

        url = f"{self.endpoint}/list?{urlencode(params)}"

        def _list():
            response = self.session.get(url, timeout=self.timeout)
            self._handle_response(response)
            return response.json()

        return self._retry_request(_list)

    def get_quota(self) -> Dict[str, Any]:
        """
        Get quota information for the tenant

        Returns:
            Dictionary with keys: tenant_id, used, limit, percentage

        Raises:
            MinIOError: For errors
        """
        params = {"tenant_id": self.tenant_id}
        url = f"{self.endpoint}/quota?{urlencode(params)}"

        def _get_quota():
            response = self.session.get(url, timeout=self.timeout)
            self._handle_response(response)
            return response.json()

        return self._retry_request(_get_quota)

    def health(self) -> Dict[str, Any]:
        """
        Check health status of the MinIO service

        Returns:
            Dictionary with keys: status, timestamp, services (optional)

        Raises:
            MinIOError: For errors
        """
        url = f"{self.endpoint}/health"

        def _health():
            response = self.session.get(url, timeout=self.timeout)
            self._handle_response(response)
            return response.json()

        return self._retry_request(_health)

    def close(self) -> None:
        """Close the client and release resources"""
        self.session.close()

    def __enter__(self):
        """Context manager entry"""
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit"""
        self.close()
        return False

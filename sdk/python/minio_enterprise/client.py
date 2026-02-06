"""MinIO Enterprise Python client implementation"""

import time
from typing import BinaryIO, Dict, Optional, Union
from urllib.parse import urljoin, urlencode

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

from .exceptions import (
    APIError,
    ConfigurationError,
    NetworkError,
    ObjectNotFoundError,
    QuotaExceededError,
)


class Config:
    """Configuration for MinIO Enterprise client

    Args:
        base_url: MinIO server base URL (e.g., "http://localhost:9000")
        tenant_id: Tenant identifier for multi-tenancy
        timeout: Request timeout in seconds (default: 30)
        retry_max: Maximum number of retry attempts (default: 3)
        retry_delay: Initial delay between retries in seconds (default: 1)
        session: Optional requests.Session to use
    """

    def __init__(
        self,
        base_url: str,
        tenant_id: str,
        timeout: int = 30,
        retry_max: int = 3,
        retry_delay: float = 1.0,
        session: Optional[requests.Session] = None,
    ):
        if not base_url:
            raise ConfigurationError("base_url is required")
        if not tenant_id:
            raise ConfigurationError("tenant_id is required")

        self.base_url = base_url.rstrip("/")
        self.tenant_id = tenant_id
        self.timeout = timeout
        self.retry_max = retry_max
        self.retry_delay = retry_delay
        self.session = session


class Client:
    """MinIO Enterprise API client

    Example:
        >>> client = Client(
        ...     base_url="http://localhost:9000",
        ...     tenant_id="550e8400-e29b-41d4-a716-446655440000"
        ... )
        >>> response = client.upload("hello.txt", b"Hello, World!")
        >>> print(response)
        {'status': 'uploaded', 'key': 'hello.txt', 'size': 13}
    """

    def __init__(
        self,
        base_url: str,
        tenant_id: str,
        timeout: int = 30,
        retry_max: int = 3,
        retry_delay: float = 1.0,
        session: Optional[requests.Session] = None,
    ):
        """Initialize MinIO Enterprise client

        Args:
            base_url: MinIO server base URL (e.g., "http://localhost:9000")
            tenant_id: Tenant identifier for multi-tenancy
            timeout: Request timeout in seconds (default: 30)
            retry_max: Maximum number of retry attempts (default: 3)
            retry_delay: Initial delay between retries in seconds (default: 1)
            session: Optional requests.Session to use
        """
        self.config = Config(
            base_url=base_url,
            tenant_id=tenant_id,
            timeout=timeout,
            retry_max=retry_max,
            retry_delay=retry_delay,
            session=session,
        )

        # Create or configure session
        if self.config.session:
            self.session = self.config.session
        else:
            self.session = self._create_session()

    def _create_session(self) -> requests.Session:
        """Create a requests session with connection pooling and retry logic"""
        session = requests.Session()

        # Configure connection pooling
        adapter = HTTPAdapter(
            pool_connections=10,
            pool_maxsize=10,
            max_retries=0,  # We handle retries manually for more control
        )
        session.mount("http://", adapter)
        session.mount("https://", adapter)

        return session

    def _get_headers(self) -> Dict[str, str]:
        """Get common headers for API requests"""
        return {
            "X-Tenant-ID": self.config.tenant_id,
        }

    def _make_request(
        self,
        method: str,
        endpoint: str,
        params: Optional[Dict] = None,
        data: Optional[bytes] = None,
        stream: bool = False,
    ) -> requests.Response:
        """Make an HTTP request with retry logic

        Args:
            method: HTTP method (GET, POST, PUT, DELETE)
            endpoint: API endpoint path
            params: Query parameters
            data: Request body data
            stream: Whether to stream the response

        Returns:
            requests.Response object

        Raises:
            NetworkError: If network communication fails
            APIError: If API returns an error
        """
        url = urljoin(self.config.base_url, endpoint)
        headers = self._get_headers()

        if data is not None:
            headers["Content-Type"] = "application/octet-stream"

        last_error = None

        for attempt in range(self.config.retry_max + 1):
            try:
                response = self.session.request(
                    method=method,
                    url=url,
                    params=params,
                    data=data,
                    headers=headers,
                    timeout=self.config.timeout,
                    stream=stream,
                )

                # Check for HTTP errors
                if response.status_code >= 400:
                    error_data = {}
                    try:
                        error_data = response.json()
                    except Exception:
                        pass

                    error_message = error_data.get("error", f"Request failed with status {response.status_code}")

                    # Determine if error is retryable
                    retryable = response.status_code >= 500

                    # Raise specific exceptions for known errors
                    if response.status_code == 403 and "quota" in error_message.lower():
                        raise QuotaExceededError(error_message)
                    elif response.status_code == 404:
                        raise ObjectNotFoundError(error_message)
                    else:
                        raise APIError(error_message, status_code=response.status_code, retryable=retryable)

                return response

            except (requests.ConnectionError, requests.Timeout) as e:
                last_error = NetworkError(f"Network error: {str(e)}", original_error=e)

                # Don't retry on the last attempt
                if attempt < self.config.retry_max:
                    # Exponential backoff: 1s, 2s, 4s, ...
                    delay = self.config.retry_delay * (2 ** attempt)
                    time.sleep(delay)
                else:
                    raise last_error

            except APIError as e:
                # Only retry if error is retryable
                if e.retryable and attempt < self.config.retry_max:
                    delay = self.config.retry_delay * (2 ** attempt)
                    time.sleep(delay)
                else:
                    raise

        # This should not be reached, but just in case
        if last_error:
            raise last_error
        raise NetworkError("Max retries exceeded")

    def upload(self, key: str, data: Union[bytes, BinaryIO]) -> Dict:
        """Upload an object to MinIO storage

        Args:
            key: Unique object key identifier (1-1024 characters)
            data: Object data as bytes or file-like object

        Returns:
            Dictionary with status, key, and size
            Example: {'status': 'uploaded', 'key': 'hello.txt', 'size': 13}

        Raises:
            ConfigurationError: If key is invalid
            QuotaExceededError: If tenant quota is exceeded
            APIError: If upload fails
            NetworkError: If network communication fails
        """
        if not key or len(key) > 1024:
            raise ConfigurationError("key must be 1-1024 characters")

        # Convert file-like objects to bytes
        if hasattr(data, "read"):
            data = data.read()

        response = self._make_request(
            method="PUT",
            endpoint="/upload",
            params={"key": key},
            data=data,
        )

        return response.json()

    def download(self, key: str) -> bytes:
        """Download an object from MinIO storage

        Args:
            key: Unique object key identifier

        Returns:
            Object data as bytes

        Raises:
            ConfigurationError: If key is invalid
            ObjectNotFoundError: If object does not exist
            APIError: If download fails
            NetworkError: If network communication fails
        """
        if not key:
            raise ConfigurationError("key cannot be empty")

        response = self._make_request(
            method="GET",
            endpoint="/download",
            params={"key": key},
        )

        return response.content

    def download_stream(self, key: str) -> requests.Response:
        """Download an object as a stream (for large files)

        Args:
            key: Unique object key identifier

        Returns:
            requests.Response object with streaming enabled
            Use response.iter_content(chunk_size=8192) to read chunks

        Raises:
            ConfigurationError: If key is invalid
            ObjectNotFoundError: If object does not exist
            APIError: If download fails
            NetworkError: If network communication fails
        """
        if not key:
            raise ConfigurationError("key cannot be empty")

        response = self._make_request(
            method="GET",
            endpoint="/download",
            params={"key": key},
            stream=True,
        )

        return response

    def delete(self, key: str) -> None:
        """Delete an object from MinIO storage

        Args:
            key: Unique object key identifier

        Raises:
            ConfigurationError: If key is invalid
            APIError: If delete fails
            NetworkError: If network communication fails
        """
        if not key:
            raise ConfigurationError("key cannot be empty")

        self._make_request(
            method="DELETE",
            endpoint="/delete",
            params={"key": key},
        )

    def get_server_info(self) -> Dict:
        """Get server version and status information

        Returns:
            Dictionary with status, version, and performance info
            Example: {'status': 'ok', 'version': '3.0.0-extreme', 'performance': '100x'}

        Raises:
            APIError: If request fails
            NetworkError: If network communication fails
        """
        response = self._make_request(
            method="GET",
            endpoint="/",
        )

        return response.json()

    def health_check(self) -> bool:
        """Check if the server is healthy and ready

        Returns:
            True if server is healthy, False otherwise
        """
        try:
            response = self._make_request(
                method="GET",
                endpoint="/minio/health/ready",
            )
            return response.status_code == 200
        except Exception:
            return False

    @property
    def tenant_id(self) -> str:
        """Get the configured tenant ID"""
        return self.config.tenant_id

    @property
    def base_url(self) -> str:
        """Get the configured base URL"""
        return self.config.base_url

    def close(self):
        """Close the session and release resources"""
        if self.session:
            self.session.close()

    def __enter__(self):
        """Context manager entry"""
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit"""
        self.close()
        return False

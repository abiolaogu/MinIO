"""MinIO Enterprise Python Client"""

import time
from typing import BinaryIO, Dict, Optional, Union
from urllib.parse import urljoin, urlencode

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

from .exceptions import APIError, NetworkError


class Config:
    """Configuration for MinIO Enterprise Client

    Args:
        base_url: MinIO server base URL (e.g., "http://localhost:9000")
        tenant_id: Tenant UUID for multi-tenancy
        timeout: HTTP timeout in seconds (default: 30)
        max_retries: Maximum number of retry attempts (default: 3)
    """

    def __init__(
        self,
        base_url: str,
        tenant_id: str,
        timeout: int = 30,
        max_retries: int = 3,
    ):
        if not base_url:
            raise ValueError("base_url is required")
        if not tenant_id:
            raise ValueError("tenant_id is required")

        self.base_url = base_url.rstrip("/")
        self.tenant_id = tenant_id
        self.timeout = timeout
        self.max_retries = max_retries


class Client:
    """MinIO Enterprise SDK Client

    Provides methods for interacting with MinIO Enterprise API including
    upload, download, and server management operations.

    Example:
        >>> from minio_enterprise import Client, Config
        >>> client = Client(Config(
        ...     base_url="http://localhost:9000",
        ...     tenant_id="550e8400-e29b-41d4-a716-446655440000"
        ... ))
        >>> with open("file.txt", "rb") as f:
        ...     response = client.upload("my-file.txt", f)
        >>> print(f"Uploaded {response['key']}")
    """

    def __init__(self, config: Config):
        """Initialize the MinIO Enterprise client

        Args:
            config: Client configuration
        """
        self.config = config
        self.session = self._create_session()

    def _create_session(self) -> requests.Session:
        """Create a requests session with retry logic and connection pooling"""
        session = requests.Session()

        # Configure retry strategy
        retry_strategy = Retry(
            total=self.config.max_retries,
            backoff_factor=1,  # Exponential backoff: 1s, 2s, 4s, ...
            status_forcelist=[429, 500, 502, 503, 504],
            allowed_methods=["HEAD", "GET", "PUT", "DELETE", "OPTIONS", "TRACE", "POST"],
        )

        # Mount adapter with retry strategy
        adapter = HTTPAdapter(
            max_retries=retry_strategy,
            pool_connections=10,
            pool_maxsize=100,
        )
        session.mount("http://", adapter)
        session.mount("https://", adapter)

        # Set default headers
        session.headers.update({
            "X-Tenant-ID": self.config.tenant_id,
            "User-Agent": "MinIO-Enterprise-Python-SDK/1.0.0",
        })

        return session

    def upload(
        self,
        key: str,
        data: Union[bytes, BinaryIO],
    ) -> Dict[str, Union[str, int]]:
        """Upload an object to MinIO

        Args:
            key: Unique object key identifier
            data: Binary data or file-like object to upload

        Returns:
            dict: Upload response with keys 'status', 'key', and 'size'

        Raises:
            APIError: If the API returns an error
            NetworkError: If a network error occurs

        Example:
            >>> # Upload from bytes
            >>> response = client.upload("test.txt", b"Hello, World!")

            >>> # Upload from file
            >>> with open("file.txt", "rb") as f:
            ...     response = client.upload("remote.txt", f)
        """
        url = f"{self.config.base_url}/upload?{urlencode({'key': key})}"

        headers = {"Content-Type": "application/octet-stream"}

        try:
            response = self.session.put(
                url,
                data=data,
                headers=headers,
                timeout=self.config.timeout,
            )

            if response.status_code != 200:
                error_data = response.json() if response.headers.get("Content-Type") == "application/json" else {}
                error_message = error_data.get("error", response.text)
                raise APIError(response.status_code, error_message)

            return response.json()

        except requests.exceptions.RequestException as e:
            raise NetworkError(str(e))

    def download(self, key: str) -> bytes:
        """Download an object from MinIO

        Args:
            key: Unique object key identifier

        Returns:
            bytes: Object data

        Raises:
            APIError: If the API returns an error (e.g., 404 not found)
            NetworkError: If a network error occurs

        Example:
            >>> data = client.download("test.txt")
            >>> print(data.decode())
        """
        url = f"{self.config.base_url}/download?{urlencode({'key': key})}"

        try:
            response = self.session.get(url, timeout=self.config.timeout)

            if response.status_code != 200:
                error_data = response.json() if response.headers.get("Content-Type") == "application/json" else {}
                error_message = error_data.get("error", response.text)
                raise APIError(response.status_code, error_message)

            return response.content

        except requests.exceptions.RequestException as e:
            raise NetworkError(str(e))

    def download_to_file(self, key: str, file_path: str) -> None:
        """Download an object and save to file

        Args:
            key: Unique object key identifier
            file_path: Local file path to save to

        Raises:
            APIError: If the API returns an error
            NetworkError: If a network error occurs
            IOError: If file cannot be written

        Example:
            >>> client.download_to_file("remote.txt", "local.txt")
        """
        data = self.download(key)
        with open(file_path, "wb") as f:
            f.write(data)

    def get_server_info(self) -> Dict[str, str]:
        """Get server information

        Returns:
            dict: Server info with keys 'status', 'version', and 'performance'

        Raises:
            APIError: If the API returns an error
            NetworkError: If a network error occurs

        Example:
            >>> info = client.get_server_info()
            >>> print(f"Version: {info['version']}")
        """
        url = f"{self.config.base_url}/"

        try:
            response = self.session.get(url, timeout=self.config.timeout)

            if response.status_code != 200:
                raise APIError(response.status_code, response.text)

            return response.json()

        except requests.exceptions.RequestException as e:
            raise NetworkError(str(e))

    def health_check(self) -> bool:
        """Perform a health check

        Returns:
            bool: True if service is healthy

        Raises:
            APIError: If the health check fails
            NetworkError: If a network error occurs

        Example:
            >>> if client.health_check():
            ...     print("Service is healthy")
        """
        url = f"{self.config.base_url}/minio/health/ready"

        try:
            response = self.session.get(url, timeout=self.config.timeout)

            if response.status_code != 200:
                raise APIError(response.status_code, response.text)

            return True

        except requests.exceptions.RequestException as e:
            raise NetworkError(str(e))

    def close(self) -> None:
        """Close the client and release resources

        Example:
            >>> client.close()
        """
        self.session.close()

    def __enter__(self):
        """Context manager entry"""
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit"""
        self.close()

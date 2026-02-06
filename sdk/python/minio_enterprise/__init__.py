"""MinIO Enterprise Python SDK

Official Python SDK for MinIO Enterprise - Ultra-high-performance object storage.

Example usage:
    >>> from minio_enterprise import Client
    >>> client = Client(
    ...     base_url="http://localhost:9000",
    ...     tenant_id="550e8400-e29b-41d4-a716-446655440000"
    ... )
    >>> response = client.upload("hello.txt", b"Hello, MinIO!")
    >>> print(response)
"""

from .client import Client, Config
from .exceptions import (
    MinIOError,
    APIError,
    ConfigurationError,
    NetworkError,
    QuotaExceededError,
    ObjectNotFoundError,
)

__version__ = "1.0.0"
__all__ = [
    "Client",
    "Config",
    "MinIOError",
    "APIError",
    "ConfigurationError",
    "NetworkError",
    "QuotaExceededError",
    "ObjectNotFoundError",
]

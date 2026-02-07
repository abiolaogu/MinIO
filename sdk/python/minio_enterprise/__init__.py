"""MinIO Enterprise Python SDK

Official Python SDK for MinIO Enterprise - Ultra-High-Performance Object Storage.
"""

from .client import Client, Config
from .exceptions import MinIOError, APIError, NetworkError

__version__ = "1.0.0"
__all__ = ["Client", "Config", "MinIOError", "APIError", "NetworkError"]

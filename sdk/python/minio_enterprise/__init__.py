"""
MinIO Enterprise Python SDK

Official Python SDK for MinIO Enterprise - Ultra-High-Performance Object Storage
"""

from .client import Client
from .exceptions import (
    MinIOError,
    AuthenticationError,
    QuotaExceededError,
    NotFoundError,
    InvalidRequestError,
)

__version__ = "1.0.0"
__author__ = "MinIO Enterprise Team"

__all__ = [
    "Client",
    "MinIOError",
    "AuthenticationError",
    "QuotaExceededError",
    "NotFoundError",
    "InvalidRequestError",
]

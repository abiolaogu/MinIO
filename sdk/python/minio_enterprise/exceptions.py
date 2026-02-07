"""Exception classes for MinIO Enterprise SDK"""


class MinIOError(Exception):
    """Base exception for MinIO Enterprise SDK"""
    pass


class APIError(MinIOError):
    """Exception raised for API errors"""

    def __init__(self, status_code: int, message: str):
        self.status_code = status_code
        self.message = message
        super().__init__(f"API error (status {status_code}): {message}")


class NetworkError(MinIOError):
    """Exception raised for network errors"""

    def __init__(self, message: str):
        self.message = message
        super().__init__(f"Network error: {message}")

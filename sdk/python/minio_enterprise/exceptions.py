"""
Exception classes for MinIO Enterprise SDK
"""


class MinIOError(Exception):
    """Base exception for all MinIO errors"""

    def __init__(self, message: str, status_code: int = None):
        super().__init__(message)
        self.status_code = status_code


class AuthenticationError(MinIOError):
    """Raised when authentication fails"""

    pass


class QuotaExceededError(MinIOError):
    """Raised when tenant quota is exceeded"""

    pass


class NotFoundError(MinIOError):
    """Raised when requested resource is not found"""

    pass


class InvalidRequestError(MinIOError):
    """Raised when request parameters are invalid"""

    pass


class ServerError(MinIOError):
    """Raised when server encounters an error"""

    pass

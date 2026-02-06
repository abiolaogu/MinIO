"""MinIO SDK exceptions"""


class MinIOError(Exception):
    """Base exception for all MinIO SDK errors"""

    def __init__(self, message, status_code=None, response_body=None):
        super().__init__(message)
        self.status_code = status_code
        self.response_body = response_body


class AuthenticationError(MinIOError):
    """Raised when authentication fails"""

    pass


class QuotaExceededError(MinIOError):
    """Raised when tenant quota is exceeded"""

    pass


class NotFoundError(MinIOError):
    """Raised when requested resource is not found"""

    pass


class ValidationError(MinIOError):
    """Raised when request validation fails"""

    pass


class RateLimitError(MinIOError):
    """Raised when rate limit is exceeded"""

    pass


class ServerError(MinIOError):
    """Raised when server returns 5xx error"""

    pass

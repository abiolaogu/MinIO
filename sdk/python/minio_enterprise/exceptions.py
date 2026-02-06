"""Exception classes for MinIO Enterprise SDK"""


class MinIOError(Exception):
    """Base exception for all MinIO Enterprise errors"""
    pass


class ConfigurationError(MinIOError):
    """Raised when client configuration is invalid"""
    pass


class NetworkError(MinIOError):
    """Raised when network communication fails"""

    def __init__(self, message, original_error=None):
        super().__init__(message)
        self.original_error = original_error


class APIError(MinIOError):
    """Raised when API returns an error response"""

    def __init__(self, message, status_code=None, retryable=False):
        super().__init__(message)
        self.status_code = status_code
        self.retryable = retryable

    def __str__(self):
        if self.status_code:
            return f"API Error (status {self.status_code}): {super().__str__()}"
        return f"API Error: {super().__str__()}"


class QuotaExceededError(APIError):
    """Raised when tenant quota is exceeded"""

    def __init__(self, message="Quota exceeded"):
        super().__init__(message, status_code=403, retryable=False)


class ObjectNotFoundError(APIError):
    """Raised when requested object is not found"""

    def __init__(self, message="Object not found", key=None):
        super().__init__(message, status_code=404, retryable=False)
        self.key = key

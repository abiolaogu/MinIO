"""MinIO SDK data models"""

from dataclasses import dataclass
from datetime import datetime
from typing import List, Optional


@dataclass
class Object:
    """Represents a MinIO object"""

    key: str
    size: int
    last_modified: datetime
    content_type: str = ""
    etag: str = ""

    @classmethod
    def from_dict(cls, data: dict) -> "Object":
        """Create Object from dictionary"""
        last_modified = data.get("last_modified", "")
        if isinstance(last_modified, str):
            try:
                last_modified = datetime.fromisoformat(last_modified.replace("Z", "+00:00"))
            except (ValueError, AttributeError):
                last_modified = datetime.now()

        return cls(
            key=data.get("key", ""),
            size=data.get("size", 0),
            last_modified=last_modified,
            content_type=data.get("content_type", ""),
            etag=data.get("etag", ""),
        )


@dataclass
class ListResponse:
    """Response from list operation"""

    objects: List[Object]
    count: int

    @classmethod
    def from_dict(cls, data: dict) -> "ListResponse":
        """Create ListResponse from dictionary"""
        objects = [Object.from_dict(obj) for obj in data.get("objects", [])]
        return cls(objects=objects, count=data.get("count", 0))


@dataclass
class QuotaInfo:
    """Tenant quota information"""

    tenant_id: str
    used: int
    limit: int
    percentage: float

    @classmethod
    def from_dict(cls, data: dict) -> "QuotaInfo":
        """Create QuotaInfo from dictionary"""
        return cls(
            tenant_id=data.get("tenant_id", ""),
            used=data.get("used", 0),
            limit=data.get("limit", 0),
            percentage=data.get("percentage", 0.0),
        )


@dataclass
class HealthStatus:
    """Service health status"""

    status: str
    timestamp: str

    @classmethod
    def from_dict(cls, data: dict) -> "HealthStatus":
        """Create HealthStatus from dictionary"""
        return cls(
            status=data.get("status", "unknown"),
            timestamp=data.get("timestamp", ""),
        )

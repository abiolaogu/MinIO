"""
Setup script for MinIO Enterprise Python SDK
"""

from setuptools import setup, find_packages
import os

# Read README for long description
readme_path = os.path.join(os.path.dirname(__file__), "README.md")
with open(readme_path, "r", encoding="utf-8") as f:
    long_description = f.read()

setup(
    name="minio-enterprise",
    version="2.0.0",
    description="Official Python SDK for MinIO Enterprise - Ultra-High-Performance Object Storage",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="MinIO Enterprise Team",
    author_email="support@minio-enterprise.com",
    url="https://github.com/abiolaogu/MinIO",
    project_urls={
        "Documentation": "https://github.com/abiolaogu/MinIO/tree/main/docs",
        "Source": "https://github.com/abiolaogu/MinIO/tree/main/sdk/python",
        "Bug Reports": "https://github.com/abiolaogu/MinIO/issues",
    },
    py_modules=["minio_enterprise"],
    python_requires=">=3.7",
    install_requires=[
        "requests>=2.25.0",
        "urllib3>=1.26.0",
    ],
    extras_require={
        "dev": [
            "pytest>=6.0",
            "pytest-cov>=2.10",
            "black>=21.0",
            "flake8>=3.9",
            "mypy>=0.900",
        ],
    },
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.7",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Filesystems",
        "Topic :: Internet :: WWW/HTTP",
    ],
    keywords="minio object-storage s3 cloud-storage enterprise",
    license="Apache License 2.0",
    zip_safe=False,
)

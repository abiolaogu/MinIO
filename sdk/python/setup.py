"""Setup script for MinIO Enterprise Python SDK"""

from setuptools import setup, find_packages

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setup(
    name="minio-enterprise",
    version="1.0.0",
    author="MinIO Enterprise Team",
    author_email="support@minio-enterprise.com",
    description="Official Python SDK for MinIO Enterprise - Ultra-High-Performance Object Storage",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/abiolaogu/MinIO",
    project_urls={
        "Bug Tracker": "https://github.com/abiolaogu/MinIO/issues",
        "Documentation": "https://github.com/abiolaogu/MinIO/tree/main/docs",
        "Source Code": "https://github.com/abiolaogu/MinIO/tree/main/sdk/python",
    },
    packages=find_packages(),
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Operating System :: OS Independent",
    ],
    python_requires=">=3.8",
    install_requires=[
        "requests>=2.31.0",
        "urllib3>=2.0.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.7.0",
            "flake8>=6.1.0",
            "mypy>=1.5.0",
        ],
    },
    keywords="minio object-storage s3 cloud-storage sdk",
)

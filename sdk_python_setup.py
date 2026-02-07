"""
Setup configuration for MinIO Enterprise Python SDK
"""

from setuptools import setup, find_packages

with open("sdk_python_README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setup(
    name="minio-enterprise-sdk",
    version="1.0.0",
    author="MinIO Enterprise Team",
    author_email="support@minio-enterprise.com",
    description="Official Python SDK for MinIO Enterprise - Ultra-high-performance object storage",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/abiolaogu/MinIO",
    project_urls={
        "Bug Tracker": "https://github.com/abiolaogu/MinIO/issues",
        "Documentation": "https://github.com/abiolaogu/MinIO/blob/main/docs/",
        "Source Code": "https://github.com/abiolaogu/MinIO",
    },
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.7",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Operating System :: OS Independent",
    ],
    package_dir={"": "."},
    packages=["minio_sdk"],
    python_requires=">=3.7",
    install_requires=[
        "requests>=2.28.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=3.0.0",
            "black>=22.0.0",
            "mypy>=0.950",
            "pylint>=2.13.0",
        ],
    },
    keywords="minio object-storage sdk api client s3 cloud storage",
    include_package_data=True,
)

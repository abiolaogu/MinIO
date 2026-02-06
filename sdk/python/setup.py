"""Setup script for MinIO Enterprise Python SDK"""

from setuptools import setup, find_packages

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setup(
    name="minio-enterprise",
    version="1.0.0",
    author="MinIO Enterprise Team",
    author_email="support@minio-enterprise.example.com",
    description="Official Python SDK for MinIO Enterprise - Ultra-high-performance object storage",
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
        "Development Status :: 5 - Production/Stable",
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
        "requests>=2.28.0",
        "urllib3>=1.26.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=0.990",
        ],
    },
    keywords="minio object-storage s3 enterprise storage cloud",
    license="Apache-2.0",
)

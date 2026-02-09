#!/bin/bash
# MinIO Enterprise Backup Verification Script
# Version: 1.0.0
# Description: Comprehensive backup verification and validation tool
# Usage: ./verify.sh <backup_name_or_path> [--detailed]

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse command line arguments
BACKUP_TO_VERIFY="${1:-}"
DETAILED_MODE=false

if [[ -z "${BACKUP_TO_VERIFY}" ]]; then
    echo "Usage: $0 <backup_name_or_path> [--detailed]"
    echo ""
    echo "Examples:"
    echo "  $0 minio_backup_full_20260209_143000"
    echo "  $0 /var/backups/minio/minio_backup_full_20260209_143000 --detailed"
    exit 1
fi

shift || true

for arg in "$@"; do
    case $arg in
        --detailed)
            DETAILED_MODE=true
            shift || true
            ;;
    esac
done

# Load configuration
DEFAULT_CONFIG="${SCRIPT_DIR}/backup.conf"
if [[ -f "${DEFAULT_CONFIG}" ]]; then
    # shellcheck source=/dev/null
    source "${DEFAULT_CONFIG}"
else
    echo "Warning: Configuration file not found: ${DEFAULT_CONFIG}"
    BACKUP_DIR="${BACKUP_DIR:-/var/backups/minio}"
fi

# Resolve backup path
if [[ -d "${BACKUP_TO_VERIFY}" ]]; then
    BACKUP_PATH="${BACKUP_TO_VERIFY}"
elif [[ -d "${BACKUP_DIR}/${BACKUP_TO_VERIFY}" ]]; then
    BACKUP_PATH="${BACKUP_DIR}/${BACKUP_TO_VERIFY}"
else
    echo "Error: Backup not found: ${BACKUP_TO_VERIFY}"
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNINGS=0

# Print functions
print_header() {
    echo ""
    echo "=========================================="
    echo "$1"
    echo "=========================================="
}

print_check() {
    local status="$1"
    local message="$2"

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    case $status in
        PASS)
            echo -e "${GREEN}✓${NC} ${message}"
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
            ;;
        FAIL)
            echo -e "${RED}✗${NC} ${message}"
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
            ;;
        WARN)
            echo -e "${YELLOW}⚠${NC} ${message}"
            WARNINGS=$((WARNINGS + 1))
            ;;
        INFO)
            echo -e "${BLUE}ℹ${NC} ${message}"
            ;;
    esac
}

# Verification functions
verify_backup_structure() {
    print_header "1. Backup Structure Verification"

    # Check backup directory exists
    if [[ -d "${BACKUP_PATH}" ]]; then
        print_check "PASS" "Backup directory exists: ${BACKUP_PATH}"
    else
        print_check "FAIL" "Backup directory not found: ${BACKUP_PATH}"
        return
    fi

    # Check expected subdirectories
    local expected_dirs=("postgresql" "redis" "minio-data" "config" "metadata")
    for dir in "${expected_dirs[@]}"; do
        if [[ -d "${BACKUP_PATH}/${dir}" ]]; then
            print_check "PASS" "Directory exists: ${dir}/"
        else
            print_check "WARN" "Directory missing: ${dir}/"
        fi
    done

    # Check metadata file
    if [[ -f "${BACKUP_PATH}/metadata/backup.info" ]]; then
        print_check "PASS" "Metadata file exists"
    else
        print_check "FAIL" "Metadata file missing"
    fi
}

verify_metadata() {
    print_header "2. Metadata Verification"

    local metadata_file="${BACKUP_PATH}/metadata/backup.info"

    if [[ ! -f "${metadata_file}" ]]; then
        print_check "FAIL" "Cannot verify metadata: file not found"
        return
    fi

    # Read and verify metadata fields
    local required_fields=("backup_name" "backup_type" "timestamp" "date")
    local found_fields=0

    while IFS='=' read -r key value; do
        if [[ " ${required_fields[@]} " =~ " ${key} " ]]; then
            print_check "PASS" "Metadata field: ${key}=${value}"
            found_fields=$((found_fields + 1))
        fi
    done < "${metadata_file}"

    if [[ ${found_fields} -eq ${#required_fields[@]} ]]; then
        print_check "PASS" "All required metadata fields present"
    else
        print_check "WARN" "Some metadata fields missing (${found_fields}/${#required_fields[@]})"
    fi

    # Display all metadata in detailed mode
    if [[ "${DETAILED_MODE}" == "true" ]]; then
        print_check "INFO" "Full metadata contents:"
        while IFS='=' read -r key value; do
            echo "      ${key}: ${value}"
        done < "${metadata_file}"
    fi
}

verify_postgresql_backup() {
    print_header "3. PostgreSQL Backup Verification"

    local pg_dir="${BACKUP_PATH}/postgresql"
    local pg_dump_sql="${pg_dir}/dump.sql"
    local pg_dump_gz="${pg_dir}/dump.sql.gz"

    if [[ ! -d "${pg_dir}" ]]; then
        print_check "WARN" "PostgreSQL backup directory not found"
        return
    fi

    # Check for dump file
    if [[ -f "${pg_dump_sql}" ]]; then
        print_check "PASS" "PostgreSQL dump found: dump.sql"

        # Get file size
        local size=$(du -h "${pg_dump_sql}" | cut -f1)
        print_check "INFO" "Dump file size: ${size}"

        # Check if file is not empty
        if [[ -s "${pg_dump_sql}" ]]; then
            print_check "PASS" "Dump file is not empty"
        else
            print_check "FAIL" "Dump file is empty"
        fi

        # Validate SQL syntax (basic check)
        if grep -q "PostgreSQL database dump" "${pg_dump_sql}" 2>/dev/null; then
            print_check "PASS" "Dump file appears to be valid PostgreSQL dump"
        else
            print_check "WARN" "Dump file format could not be verified"
        fi

        # Count tables in dump (if detailed mode)
        if [[ "${DETAILED_MODE}" == "true" ]]; then
            local table_count=$(grep -c "CREATE TABLE" "${pg_dump_sql}" 2>/dev/null || echo "0")
            print_check "INFO" "Tables in dump: ${table_count}"
        fi

    elif [[ -f "${pg_dump_gz}" ]]; then
        print_check "PASS" "PostgreSQL dump found (compressed): dump.sql.gz"

        # Get file size
        local size=$(du -h "${pg_dump_gz}" | cut -f1)
        print_check "INFO" "Compressed dump size: ${size}"

        # Test gzip integrity
        if gzip -t "${pg_dump_gz}" 2>/dev/null; then
            print_check "PASS" "Compressed dump integrity verified"
        else
            print_check "FAIL" "Compressed dump is corrupted"
        fi

        # Get uncompressed size
        local uncompressed_size=$(gzip -l "${pg_dump_gz}" | tail -1 | awk '{print $2}')
        print_check "INFO" "Uncompressed size: $(numfmt --to=iec-i --suffix=B ${uncompressed_size})"

    else
        print_check "FAIL" "PostgreSQL dump not found"
    fi
}

verify_redis_backup() {
    print_header "4. Redis Backup Verification"

    local redis_dir="${BACKUP_PATH}/redis"
    local redis_dump="${redis_dir}/dump.rdb"
    local redis_dump_gz="${redis_dir}/dump.rdb.gz"

    if [[ ! -d "${redis_dir}" ]]; then
        print_check "WARN" "Redis backup directory not found"
        return
    fi

    # Check for Redis dump file
    if [[ -f "${redis_dump}" ]]; then
        print_check "PASS" "Redis dump found: dump.rdb"

        # Get file size
        local size=$(du -h "${redis_dump}" | cut -f1)
        print_check "INFO" "Redis dump size: ${size}"

        # Check if file is not empty
        if [[ -s "${redis_dump}" ]]; then
            print_check "PASS" "Redis dump is not empty"
        else
            print_check "WARN" "Redis dump is empty (Redis might have been empty)"
        fi

        # Verify Redis RDB magic header (REDIS)
        if head -c 5 "${redis_dump}" | grep -q "REDIS"; then
            print_check "PASS" "Redis RDB format verified"
        else
            print_check "FAIL" "Invalid Redis RDB format"
        fi

    elif [[ -f "${redis_dump_gz}" ]]; then
        print_check "PASS" "Redis dump found (compressed): dump.rdb.gz"

        # Get file size
        local size=$(du -h "${redis_dump_gz}" | cut -f1)
        print_check "INFO" "Compressed dump size: ${size}"

        # Test gzip integrity
        if gzip -t "${redis_dump_gz}" 2>/dev/null; then
            print_check "PASS" "Compressed dump integrity verified"
        else
            print_check "FAIL" "Compressed dump is corrupted"
        fi

    else
        print_check "WARN" "Redis dump not found"
    fi
}

verify_minio_data() {
    print_header "5. MinIO Data Backup Verification"

    local minio_dir="${BACKUP_PATH}/minio-data"

    if [[ ! -d "${minio_dir}" ]]; then
        print_check "WARN" "MinIO data backup not found"
        return
    fi

    print_check "PASS" "MinIO data directory exists"

    # Count files and directories
    local file_count=$(find "${minio_dir}" -type f 2>/dev/null | wc -l)
    local dir_count=$(find "${minio_dir}" -type d 2>/dev/null | wc -l)

    print_check "INFO" "Files backed up: ${file_count}"
    print_check "INFO" "Directories backed up: ${dir_count}"

    # Calculate total size
    local total_size=$(du -sh "${minio_dir}" 2>/dev/null | cut -f1)
    print_check "INFO" "Total MinIO data size: ${total_size}"

    # Check for data
    if [[ ${file_count} -gt 0 ]]; then
        print_check "PASS" "MinIO data contains files"
    else
        print_check "WARN" "MinIO data backup is empty"
    fi

    # Detailed file listing in detailed mode
    if [[ "${DETAILED_MODE}" == "true" ]]; then
        print_check "INFO" "Top-level structure:"
        ls -lh "${minio_dir}" 2>/dev/null | head -20 | while read line; do
            echo "      ${line}"
        done
    fi
}

verify_config_backup() {
    print_header "6. Configuration Backup Verification"

    local config_dir="${BACKUP_PATH}/config"

    if [[ ! -d "${config_dir}" ]]; then
        print_check "WARN" "Configuration backup not found"
        return
    fi

    print_check "PASS" "Configuration directory exists"

    # Check for specific config directories
    local config_subdirs=("minio" "docker" "configs")
    local found_configs=0

    for subdir in "${config_subdirs[@]}"; do
        if [[ -d "${config_dir}/${subdir}" ]]; then
            print_check "PASS" "Configuration found: ${subdir}/"
            found_configs=$((found_configs + 1))

            # Count files in config directory
            local file_count=$(find "${config_dir}/${subdir}" -type f 2>/dev/null | wc -l)
            print_check "INFO" "  Files in ${subdir}: ${file_count}"
        else
            print_check "WARN" "Configuration missing: ${subdir}/"
        fi
    done

    if [[ ${found_configs} -gt 0 ]]; then
        print_check "PASS" "At least one configuration backup found"
    else
        print_check "FAIL" "No configuration backups found"
    fi
}

verify_backup_age() {
    print_header "7. Backup Age Verification"

    local metadata_file="${BACKUP_PATH}/metadata/backup.info"

    if [[ ! -f "${metadata_file}" ]]; then
        print_check "WARN" "Cannot verify age: metadata not found"
        return
    fi

    # Get backup timestamp
    local backup_date=$(grep "^date=" "${metadata_file}" | cut -d= -f2-)

    if [[ -n "${backup_date}" ]]; then
        print_check "INFO" "Backup date: ${backup_date}"

        # Calculate age
        local backup_epoch=$(date -d "${backup_date}" +%s 2>/dev/null || echo "0")
        local current_epoch=$(date +%s)
        local age_seconds=$((current_epoch - backup_epoch))
        local age_days=$((age_seconds / 86400))
        local age_hours=$(((age_seconds % 86400) / 3600))

        print_check "INFO" "Backup age: ${age_days} days, ${age_hours} hours"

        # Warn if backup is old
        if [[ ${age_days} -gt 7 ]]; then
            print_check "WARN" "Backup is more than 7 days old"
        elif [[ ${age_days} -gt 30 ]]; then
            print_check "FAIL" "Backup is more than 30 days old - may be unreliable"
        else
            print_check "PASS" "Backup age is acceptable"
        fi
    else
        print_check "WARN" "Could not determine backup date"
    fi
}

verify_permissions() {
    print_header "8. File Permissions Verification"

    # Check backup directory permissions
    if [[ -r "${BACKUP_PATH}" ]]; then
        print_check "PASS" "Backup directory is readable"
    else
        print_check "FAIL" "Backup directory is not readable"
    fi

    # Check metadata file permissions
    if [[ -r "${BACKUP_PATH}/metadata/backup.info" ]]; then
        print_check "PASS" "Metadata file is readable"
    else
        print_check "WARN" "Metadata file is not readable"
    fi

    # Check PostgreSQL dump permissions
    if [[ -f "${BACKUP_PATH}/postgresql/dump.sql" ]]; then
        if [[ -r "${BACKUP_PATH}/postgresql/dump.sql" ]]; then
            print_check "PASS" "PostgreSQL dump is readable"
        else
            print_check "FAIL" "PostgreSQL dump is not readable"
        fi
    fi
}

generate_verification_report() {
    print_header "Verification Summary"

    local total=$((PASSED_CHECKS + FAILED_CHECKS))
    local success_rate=0

    if [[ ${total} -gt 0 ]]; then
        success_rate=$(( (PASSED_CHECKS * 100) / total ))
    fi

    echo ""
    echo "  Total checks:   ${TOTAL_CHECKS}"
    echo "  Passed:         ${GREEN}${PASSED_CHECKS}${NC}"
    echo "  Failed:         ${RED}${FAILED_CHECKS}${NC}"
    echo "  Warnings:       ${YELLOW}${WARNINGS}${NC}"
    echo "  Success rate:   ${success_rate}%"
    echo ""

    # Overall status
    if [[ ${FAILED_CHECKS} -eq 0 ]]; then
        if [[ ${WARNINGS} -eq 0 ]]; then
            echo -e "${GREEN}✓ Backup verification PASSED with no warnings${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠ Backup verification PASSED with warnings${NC}"
            return 0
        fi
    else
        echo -e "${RED}✗ Backup verification FAILED${NC}"
        return 1
    fi
}

# Main execution
main() {
    echo "=========================================="
    echo "MinIO Enterprise Backup Verification"
    echo "=========================================="
    echo ""
    echo "Backup path: ${BACKUP_PATH}"
    echo "Detailed mode: ${DETAILED_MODE}"
    echo ""

    # Run all verification checks
    verify_backup_structure
    verify_metadata
    verify_postgresql_backup
    verify_redis_backup
    verify_minio_data
    verify_config_backup
    verify_backup_age
    verify_permissions

    # Generate final report
    generate_verification_report
}

# Run main function
main
exit $?

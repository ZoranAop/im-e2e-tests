#!/usr/bin/env bash
# Database Utility Functions
# Source after utils.sh or config.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! declare -f log_pass &>/dev/null; then
    if [ -f "${SCRIPT_DIR}/../performance/config.sh" ]; then
        source "${SCRIPT_DIR}/../performance/config.sh"
    fi
fi

# MYSQL_* provided by config.sh; MONGO_* defined here
MONGO_HOST="${MONGO_HOST:-localhost}"
MONGO_PORT="${MONGO_PORT:-27017}"
MONGO_DB="${MONGO_DB:-imdb}"

# MySQL connection check
check_mysql() {
    if [ -z "${MYSQL_PASS}" ]; then
        log_skip "MYSQL_PASS not set, skipping MySQL check"
        return 1
    fi
    if command -v mysql &>/dev/null; then
        if mysql -h"${MYSQL_HOST}" -P"${MYSQL_PORT}" -u"${MYSQL_USER}" -p"${MYSQL_PASS}" -e "SELECT 1;" &>/dev/null; then
            log_pass "MySQL connection OK (${MYSQL_HOST}:${MYSQL_PORT})"
            return 0
        fi
    fi
    log_fail "MySQL connection failed (${MYSQL_HOST}:${MYSQL_PORT})"
    return 1
}

# MySQL query helper
mysql_query() {
    local sql="$1"
    if [ -z "${MYSQL_PASS}" ]; then
        echo "ERROR: MYSQL_PASS not set"
        return 1
    fi
    mysql -h"${MYSQL_HOST}" -P"${MYSQL_PORT}" -u"${MYSQL_USER}" -p"${MYSQL_PASS}" -e "${sql}" 2>/dev/null || echo ""
}

# Count messages across all 128 shards (t_messages_0 through t_messages_127)
count_all_messages() {
    local total=0
    for i in $(seq 0 127); do
        local cnt=$(mysql_query "SELECT COUNT(*) FROM ${MYSQL_DB}.t_messages_${i};" | tail -1)
        cnt="${cnt:-0}"
        total=$((total + cnt))
    done
    echo "${total}"
}

# MongoDB connection check
check_mongo() {
    if command -v mongosh &>/dev/null; then
        if mongosh "mongodb://${MONGO_HOST}:${MONGO_PORT}/${MONGO_DB}" --eval "db.runCommand({ping:1})" --quiet &>/dev/null 2>&1; then
            log_pass "MongoDB connection OK (${MONGO_HOST}:${MONGO_PORT})"
            return 0
        fi
    elif command -v mongo &>/dev/null; then
        if mongo "${MONGO_HOST}:${MONGO_PORT}/${MONGO_DB}" --eval "db.runCommand({ping:1})" --quiet &>/dev/null 2>&1; then
            log_pass "MongoDB connection OK (${MONGO_HOST}:${MONGO_PORT})"
            return 0
        fi
    fi
    log_skip "MongoDB not available or not configured"
    return 1
}

# MongoDB query helper
mongo_query() {
    local js="$1"
    if command -v mongosh &>/dev/null; then
        mongosh "mongodb://${MONGO_HOST}:${MONGO_PORT}/${MONGO_DB}" --eval "${js}" --quiet 2>/dev/null || echo ""
    elif command -v mongo &>/dev/null; then
        mongo "${MONGO_HOST}:${MONGO_PORT}/${MONGO_DB}" --eval "${js}" --quiet 2>/dev/null || echo ""
    else
        echo "ERROR: No mongo client available"
    fi
}

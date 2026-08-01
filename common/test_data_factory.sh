#!/usr/bin/env bash
# ============================================================
# Test Data Factory
# ============================================================
# Generate test users, messages, groups for performance testing
#
# Usage: source common/test_data_factory.sh
# ============================================================

set -euo pipefail

generate_user_prefix() {
    local scenario="$1"
    case "${scenario}" in
        single) echo "SC_U_" ;;
        group)  echo "GC_U_" ;;
        chatroom) echo "CR_U_" ;;
        *)      echo "TEST_U_" ;;
    esac
}

generate_test_users() {
    local count="$1" prefix="$2" start="${3:-0}"
    local end=$((start + count - 1))
    log_info "Generating ${count} test users (${prefix}${start}..${prefix}${end})..."
    for i in $(seq "${start}" "${end}"); do
        echo "${prefix}${i}"
    done
}

generate_test_message() {
    local sender="$1" target="$2" seq="$3"
    echo "{\"sender\":\"${sender}\",\"target\":\"${target}\",\"content\":{\"type\":1,\"searchableContent\":\"test-msg-${seq}-$(date +%s)\"}}"
}

generate_group_config() {
    local group_count="$1" member_count="$2" prefix="${3:-G_}"
    cat << EOF
Group Configuration:
  Groups: ${group_count}
  Members per group: ${member_count}
  Total members: $((group_count * member_count))
  Group prefix: ${prefix}
  Group IDs: ${prefix}0..${prefix}$((group_count - 1))
EOF
}

cleanup_test_data() {
    local prefix="$1"
    log_warn "Cleanup test data with prefix: ${prefix}"
    log_info "  Manual cleanup required via Admin API or database"
    log_info "  DELETE FROM users WHERE user_id LIKE '${prefix}%';"
    log_info "  DELETE FROM groups WHERE group_id LIKE '${prefix}%';"
}

#!/bin/bash
# Fetch IPv4 CIDR ranges from iplist.opencck.org for specified groups/sites.
#
# Usage:
#   # All Russian service groups (default: vk, russia, yandex)
#   ./routes/fetch-iplist.opencck.sh
#
#   # Specific services
#   ./routes/fetch-iplist.opencck.sh --site ozon.ru --site cdek.ru
#
#   # By group
#   ./routes/fetch-iplist.opencck.sh --group yandex
#
#   # Mix groups and sites
#   ./routes/fetch-iplist.opencck.sh --group yandex --site ozon.ru --site cdek.ru
#
#   # List available services
#   ./routes/fetch-iplist.opencck.sh --list
#
#   # Different instance (e.g. blocked services)
#   ./routes/fetch-iplist.opencck.sh --base-url https://iplist.opencck.org --list
#
#   sudo ./interface.sh --reload-routes --name <if_name>

set -euo pipefail

BASE_URL="https://russia.iplist.opencck.org"
FILTER_QUERY=""
FILTER_LIST=""
ACTION="fetch"

while [ $# -gt 0 ]; do
  case "$1" in
    --base-url)
      BASE_URL="$2"; shift; shift ;;
    --group)
      FILTER_QUERY="${FILTER_QUERY}&group=$2"
      FILTER_LIST="${FILTER_LIST:+$FILTER_LIST, }$2"
      shift; shift ;;
    --site)
      FILTER_QUERY="${FILTER_QUERY}&site=$2"
      FILTER_LIST="${FILTER_LIST:+$FILTER_LIST, }$2"
      shift; shift ;;
    --list)
      ACTION="list"; shift ;;
    --help|-h)
      cat <<EOF
Usage: $0 [options]

Options:
  --site <name>     Fetch CIDRs for a specific service (repeatable)
  --group <name>    Fetch CIDRs for a service group (repeatable)
  --list            List all available services and groups
  --base-url <url>  API base URL (default: https://russia.iplist.opencck.org)
  --help            Show this help

Without --site or --group, fetches all services from groups: vk, russia, yandex.

Examples:
  $0                                          # All Russian services
  $0 --list                                   # Show available services
  $0 --site ozon.ru --site cdek.ru            # Specific services
  $0 --group yandex                           # All Yandex services
  $0 --group yandex --site ozon.ru            # Mix group + site
  $0 --base-url https://iplist.opencck.org --list  # Global instance
EOF
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [ "$ACTION" = "list" ]; then
  echo "Available services at ${BASE_URL}:"
  echo ""
  wget -q -O - "${BASE_URL}/?format=json&data=cidr4" \
    | tr ',' '\n' | grep -o '"[^"]*":' | tr -d '":' | sort -u
  exit 0
fi

# Default: all Russian service groups
if [ -z "$FILTER_QUERY" ]; then
  FILTER_QUERY="&group=vk&group=russia&group=yandex"
  FILTER_LIST="vk, russia, yandex"
fi

QUERY="format=text&data=cidr4${FILTER_QUERY}"

echo "# iplist.opencck.org — ${FILTER_LIST}"
echo "# Source: ${BASE_URL}/?${QUERY}"
echo "# Generated: $(date -u '+%Y-%m-%d %H:%M UTC')"

wget -q -O - "${BASE_URL}/?${QUERY}"

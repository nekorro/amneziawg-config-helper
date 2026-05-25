#!/bin/bash
# Fetch IPv4 CIDR ranges from iplist.opencck.org for specified groups.
#
# Usage:
#   # All Russian service groups (default)
#   ./routes/fetch-iplist.opencck.sh
#
#   # Custom groups
#   ./routes/fetch-iplist.opencck.sh --group vk --group yandex
#
#   # Different instance
#   ./routes/fetch-iplist.opencck.sh --base-url https://iplist.opencck.org --group youtube
#
#   sudo ./interface.sh --reload-routes --name <if_name>

set -euo pipefail

BASE_URL="https://russia.iplist.opencck.org"
GROUP_QUERY=""
GROUP_LIST=""

while [ $# -gt 0 ]; do
  case "$1" in
    --base-url)
      BASE_URL="$2"; shift; shift ;;
    --group)
      GROUP_QUERY="${GROUP_QUERY}&group=$2"
      GROUP_LIST="${GROUP_LIST:+$GROUP_LIST, }$2"
      shift; shift ;;
    --help|-h)
      echo "Usage: $0 [--base-url <url>] [--group <name>]..."
      echo ""
      echo "Options:"
      echo "  --base-url  API base URL (default: https://russia.iplist.opencck.org)"
      echo "  --group     Group to fetch (repeatable). Default: vk, russia, yandex"
      echo ""
      echo "Examples:"
      echo "  $0"
      echo "  $0 --group vk --group yandex"
      echo "  $0 --base-url https://iplist.opencck.org --group youtube --group google"
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Default groups
if [ -z "$GROUP_QUERY" ]; then
  GROUP_QUERY="&group=vk&group=russia&group=yandex"
  GROUP_LIST="vk, russia, yandex"
fi

QUERY="format=text&data=cidr4${GROUP_QUERY}"

echo "# iplist.opencck.org — groups: ${GROUP_LIST}"
echo "# Source: ${BASE_URL}/?${QUERY}"
echo "# Generated: $(date -u '+%Y-%m-%d %H:%M UTC')"

wget -q -O - "${BASE_URL}/?${QUERY}"

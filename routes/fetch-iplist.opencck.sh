#!/bin/bash
# Fetch IPv4 CIDR ranges from iplist.opencck.org for specified groups.
#
# Usage:
#   # All Russian service groups (default)
#   ./routes/fetch-opencck.sh > /etc/amnezia/amneziawg/routes/<if_name>/local/ru-services.txt
#
#   # Custom instance and groups
#   ./routes/fetch-opencck.sh --base-url https://iplist.opencck.org --group youtube --group google
#
#   sudo ./interface.sh --reload-routes --name <if_name>

set -euo pipefail

BASE_URL="https://russia.iplist.opencck.org"
GROUPS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift ;;
    --group)    GROUPS+=("$2"); shift ;;
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
  shift
done

# Default groups for russia instance
if [ ${#GROUPS[@]} -eq 0 ]; then
  GROUPS=(vk russia yandex)
fi

# Build query string
QUERY="format=text&data=cidr4"
for g in "${GROUPS[@]}"; do
  QUERY="${QUERY}&group=${g}"
done

echo "# iplist.opencck.org — groups: ${GROUPS[*]}"
echo "# Source: ${BASE_URL}/?${QUERY}"
echo "# Generated: $(date -u '+%Y-%m-%d %H:%M UTC')"

wget -q -O - "${BASE_URL}/?${QUERY}"

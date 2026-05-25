#!/bin/bash
# Fetch all IPv4 ranges for a country from regional internet registries.
# Sources: RIPE, ARIN, APNIC, LACNIC, AFRINIC delegated stats.
#
# Usage:
#   ./routes/fetch-country.sh RU > /etc/amnezia/amneziawg/routes/<if_name>/local/ru.txt
#   ./routes/fetch-country.sh US > /etc/amnezia/amneziawg/routes/<if_name>/local/us.txt
#   sudo ./interface.sh --reload-routes --name <if_name>

set -euo pipefail

CC="${1:-}"
if [ -z "$CC" ]; then
  echo "Usage: $0 <country_code>" >&2
  echo "Example: $0 RU" >&2
  exit 1
fi
CC=$(echo "$CC" | tr '[:lower:]' '[:upper:]')

REGISTRIES="
https://ftp.ripe.net/pub/stats/ripencc/delegated-ripencc-latest
https://ftp.arin.net/pub/stats/arin/delegated-arin-extended-latest
https://ftp.apnic.net/pub/stats/apnic/delegated-apnic-latest
https://ftp.lacnic.net/pub/stats/lacnic/delegated-lacnic-latest
https://ftp.afrinic.net/pub/stats/afrinic/delegated-afrinic-latest
"

echo "# $CC IPv4 ranges"
echo "# Generated: $(date -u '+%Y-%m-%d %H:%M UTC')"

for url in $REGISTRIES; do
  wget -q -O - "$url" 2>/dev/null
done \
  | awk -F'|' -v cc="$CC" '$2 == cc && $3 == "ipv4" {
      ip = $4
      hosts = $5
      prefix = 32
      n = hosts
      while (n > 1) { n /= 2; prefix-- }
      print ip "/" prefix
    }'

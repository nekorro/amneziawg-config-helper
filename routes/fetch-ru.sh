#!/bin/bash
# Fetch all Russian IP ranges from RIPE and save as a routes file.
# Source: RIPE NCC delegated stats (official regional registry for RU).
#
# Usage:
#   ./routes/fetch-ru.sh > /etc/amnezia/amneziawg/routes/<if_name>/local/ru.txt
#   sudo ./interface.sh --reload-routes --name <if_name>

set -euo pipefail

URL="https://ftp.ripe.net/pub/stats/ripencc/delegated-ripencc-latest"

wget -q -O - "$URL" \
  | awk -F'|' '$2 == "RU" && $3 == "ipv4" {
      ip = $4
      hosts = $5
      # Convert host count to CIDR prefix length
      prefix = 32
      n = hosts
      while (n > 1) { n /= 2; prefix-- }
      print ip "/" prefix
    }'

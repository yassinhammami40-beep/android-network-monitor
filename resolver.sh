#!/data/data/com.termux/files/usr/bin/bash
################################################################################
# Domain Resolver - runs INSIDE Termux app (has dig/curl but no /proc access).
# Watches the queue file written by collector.sh (running via adb shell) and
# resolves each IP to a domain, writing clean results to resolved_domains.csv
################################################################################

BASE_DIR="/sdcard/Download/network-monitor"
QUEUE_FILE="$BASE_DIR/.queue/raw_ips.txt"
DOMAINS_DIR="$BASE_DIR/domains"
CACHE_DIR="$BASE_DIR/.cache"
DNS_CACHE="$CACHE_DIR/dns_cache.db"
DNS_RESOLVED="$DOMAINS_DIR/resolved_domains.csv"
LOGGED_IPS="$CACHE_DIR/logged_ips.db"
RESOLUTION_TIMEOUT=3
REPORT_INTERVAL_CYCLES=12   # regenerate report every ~60s (12 x 5s sleep)

mkdir -p "$DOMAINS_DIR" "$CACHE_DIR" 2>/dev/null

if [ ! -f "$DNS_RESOLVED" ]; then
  echo "TIMESTAMP,IP,DOMAIN,CONFIDENCE,SOURCE" > "$DNS_RESOLVED"
fi
touch "$DNS_CACHE" "$LOGGED_IPS"

has_binary() { command -v "$1" >/dev/null 2>&1; }

# Joins today's ip_history.csv (has package names, written by collector.sh)
# with resolved_domains.csv (has domains/orgs, written by this script) on IP,
# producing a package -> domain report. Runs periodically, not every cycle,
# since it re-scans the full day's history file each time.
generate_package_report() {
  local ip_history="$BASE_DIR/ip_history_$(date +%Y-%m-%d).csv"
  local report="$DOMAINS_DIR/package_domain_report_$(date +%Y-%m-%d).csv"

  [ -f "$ip_history" ] || return
  [ -f "$DNS_RESOLVED" ] || return
  echo "PACKAGE,DOMAIN,IP" > "$report"
  awk -F',' '
    NR==FNR {
      if (FNR == 1) next
      ip = $2; domain = $3
      gsub(/^"|"$/, "", domain)
      if (!(ip in domain_of)) domain_of[ip] = domain
      next
    }
    FNR == 1 { next }
    {
      ip = $2; pkg = $6
      if (ip in domain_of && pkg != "") {
        pair = pkg "," domain_of[ip] "," ip
        if (!(pair in seen)) { seen[pair] = 1; print pair }
      }
    }
  ' "$DNS_RESOLVED" "$ip_history" | sort -u >> "$report"
}
get_domain() {
  local ip="$1"
  local domain
  case "$ip" in
    127.*|localhost) echo "localhost"; return ;;
    192.168.*|10.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*) echo "private"; return ;;
    0.0.0.0|255.255.255.255|169.254.*) echo "reserved"; return ;;
  esac
  domain=$(grep "^${ip}=" "$DNS_CACHE" 2>/dev/null | cut -d'=' -f2 | head -1)
  if [ -n "$domain" ]; then
    echo "$domain"
    return
  fi
  if has_binary dig; then
    domain=$(timeout "$RESOLUTION_TIMEOUT" dig +short -x "$ip" 2>/dev/null | grep -v "^;" | tail -1 | sed 's/\.$//')
    if [ -n "$domain" ] && [ "$domain" != "." ]; then
      local main_domain
      main_domain=$(echo "$domain" | awk -F. '{if (NF>2) print $(NF-1)"."$NF; else print $0}')
      echo "${ip}=${main_domain}" >> "$DNS_CACHE"
      echo "$main_domain"
      return
    fi
  fi
  if has_binary curl && has_binary jq; then
    domain=$(timeout "$RESOLUTION_TIMEOUT" curl -s "http://ip-api.com/json/${ip}?fields=reverse" 2>/dev/null | jq -r '.reverse // empty' 2>/dev/null | sed 's/\.$//')
    if [ -n "$domain" ] && [ "$domain" != "null" ]; then
      local main_domain
      main_domain=$(echo "$domain" | awk -F. '{if (NF>2) print $(NF-1)"."$NF; else print $0}')
      echo "${ip}=${main_domain}" >> "$DNS_CACHE"
      echo "$main_domain"
      return
    fi
  fi
  # Fallback: no hostname found via reverse DNS. Try ASN/org lookup instead -
  # every routed IP belongs to a registered org, even without a PTR record.
  if has_binary curl; then
    local org
    org=$(timeout "$RESOLUTION_TIMEOUT" curl -s "https://ipinfo.io/${ip}/org" 2>/dev/null | tr -d '\r\n')
    if [ -n "$org" ]; then
      org=$(echo "$org" | sed 's/^AS[0-9]* //')
      echo "${ip}=org:${org}" >> "$DNS_CACHE"
      echo "org:${org}"
      return
    fi
  fi
  echo "${ip}=unknown" >> "$DNS_CACHE"
  echo "unknown"
}
echo "Resolver started. Watching $QUEUE_FILE ..."
REPORT_CYCLE_COUNT=0
while true; do
  if [ -f "$QUEUE_FILE" ]; then
    # Dedup IPs from this cycle's queue before resolving (avoid redundant lookups)
    cut -d'|' -f1 "$QUEUE_FILE" | sort -u | while read -r ip; do
      [ -z "$ip" ] && continue
      domain=$(get_domain "$ip")
      ts=$(date "+%H:%M:%S")
      case "$domain" in
        unknown) conf="low" ;;
        org:*) conf="medium" ;;
        *) conf="high" ;;
      esac
      # CSV-safe: wrap the domain field in quotes if it contains a comma
      # (org: lookups often do, e.g. "Cloudflare, Inc.")
      case "$domain" in
        *,*) csv_domain="\"$domain\"" ;;
        *) csv_domain="$domain" ;;
      esac
      # Only log if this exact ip=domain pair hasn't been logged before
      pair="${ip}=${domain}"
      if ! grep -qxF "$pair" "$LOGGED_IPS" 2>/dev/null; then
        echo "$ts,$ip,$csv_domain,$conf,dig-or-curl" >> "$DNS_RESOLVED"
        echo "$pair" >> "$LOGGED_IPS"
      fi
    done
  fi
  REPORT_CYCLE_COUNT=$((REPORT_CYCLE_COUNT + 1))
  if [ "$REPORT_CYCLE_COUNT" -ge "$REPORT_INTERVAL_CYCLES" ]; then
    generate_package_report
    REPORT_CYCLE_COUNT=0
  fi
  sleep 5
done


#!/system/bin/sh

################################################################################
# Android Network Monitor v2.0 - Advanced Network Analysis
# Features:
#  - Full IPv4 and IPv6 support with IPv4-mapped IPv6 handling
#  - TCP/UDP connection tracking with lifecycle management
#  - DNS correlation and caching
#  - Connection state tracking (NEW, ACTIVE, CLOSED)
#  - Multiple output formats (TXT, CSV, JSON)
#  - Comprehensive logging and metrics
################################################################################

# Directory Structure
BASE_DIR="/sdcard/Download/network-monitor"
LOGS_DIR="$BASE_DIR/logs"
ACTIVITY_DIR="$LOGS_DIR/activity"
DOMAINS_DIR="$BASE_DIR/domains"
STATS_DIR="$BASE_DIR/stats"
CACHE_DIR="/data/local/tmp/.net_monitor_cache"

# Output Files (.txt for browser compatibility)
CURRENT_LOG="$ACTIVITY_DIR/current.txt"
INTERFACES_LOG="$ACTIVITY_DIR/interfaces.txt"
TCP_LOG="$ACTIVITY_DIR/tcp_connections.txt"
UDP_LOG="$ACTIVITY_DIR/udp_connections.txt"
CONNECTION_STATE="$ACTIVITY_DIR/connection_state.csv"

# DNS and Domain Files
DNS_CACHE="$CACHE_DIR/dns_cache.db"
DNS_RESOLVED="$DOMAINS_DIR/resolved_domains.csv"
IP_HISTORY="$BASE_DIR/ip_history_$(date +%Y-%m-%d).csv"
DOMAIN_HISTORY="$DOMAINS_DIR/domain_history_$(date +%Y-%m-%d).csv"
DOMAIN_CORRELATION="$DOMAINS_DIR/domain_correlation.csv"

# Statistics
STATS_SUMMARY="$STATS_DIR/summary_$(date +%Y-%m-%d).txt"
STATS_JSON="$STATS_DIR/stats_$(date +%Y-%m-%d).json"

# Temporary Files
TEMP_IPS="/data/local/tmp/current_ips.tmp"
TEMP_CONNECTIONS="/data/local/tmp/connections.tmp"
TEMP_STATE="/data/local/tmp/connection_state.tmp"
FD_MAP="/data/local/tmp/fd_inodes.tmp"
PREV_STATE="/data/local/tmp/prev_state.tmp"

# Constants
RESOLUTION_TIMEOUT=3
DNS_CACHE_TTL=3600  # 1 hour

################################################################################
# Initialize Directories & Cleanup
################################################################################

init_directories() {
  mkdir -p "$LOGS_DIR" "$ACTIVITY_DIR" "$DOMAINS_DIR" "$STATS_DIR" "$CACHE_DIR" 2>/dev/null
  
  # Keep only current logs (delete old activity logs, keep history)
  find "$ACTIVITY_DIR" -type f -mtime +0 -delete 2>/dev/null
  
  # Clean temporary files
  rm -f "$TEMP_IPS" "$TEMP_CONNECTIONS" "$TEMP_STATE" "$FD_MAP" /data/local/tmp/*_processed.tmp 2>/dev/null
}

# Initialize on startup
if [ ! -d "$BASE_DIR" ]; then
  init_directories
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Network Monitor v2.0 initialized" > "$LOGS_DIR/monitor.log"
fi

################################################################################
# DNS Resolution & Caching Functions
################################################################################

get_domain() {
  local ip="$1"
  local domain
  
  # Skip private/local IPs
  case "$ip" in
    127.*|localhost|::1|0000:0000:0000:0000:0000:0000:0000:0001) echo "localhost"; return ;;
    192.168.*|10.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*) echo "private"; return ;;
    0.0.0.0|255.255.255.255|169.254.*) echo "reserved"; return ;;
  esac
  
  # IPv6 link-local
  case "$ip" in
    fe80:*|ff00:*|ff02:*) echo "link-local"; return ;;
  esac
  
  # Check cache first
  if [ -f "$DNS_CACHE" ]; then
    domain=$(grep "^${ip}=" "$DNS_CACHE" 2>/dev/null | cut -d'=' -f2 | head -1)
    if [ -n "$domain" ]; then
      echo "$domain"
      return
    fi
  fi
  
  # Resolve via ip-api.com (with timeout and error handling)
  domain=$(timeout "$RESOLUTION_TIMEOUT" sh -c "echo -e 'GET /json/$ip?fields=reverse HTTP/1.1\r\nHost: ip-api.com\r\nConnection: close\r\n\r\n' | nc -w 2 ip-api.com 80 2>/dev/null | sed -n 's/.*\"reverse\":\"\([^\"]*\)\".*/\1/p'" 2>/dev/null)
  
  # Extract main domain
  if [ -n "$domain" ]; then
    local main_domain=$(echo "$domain" | awk -F. '{if (NF>2) print $(NF-1)"."$NF; else print $0}')
    echo "${ip}=${main_domain}" >> "$DNS_CACHE"
    echo "$main_domain"
  else
    echo "${ip}=unknown" >> "$DNS_CACHE"
    echo "unknown"
  fi
}

################################################################################
# UID to Package Resolution (handles multiple processes)
################################################################################

resolve_uid() {
  uid=$1
  cfile="$CACHE_DIR/u_$uid"
  
  if [ -f "$cfile" ]; then
    cat "$cfile"
  else
    # Get primary package
    pkg=$(pm list packages --uid "$uid" 2>/dev/null | cut -d':' -f2 | awk '{print $1}' | head -n1)
    [ -z "$pkg" ] && pkg="system"
    echo "$pkg" > "$cfile"
    echo "$pkg"
  fi
}

# Get all packages for a UID
get_all_packages_for_uid() {
  uid=$1
  pm list packages --uid "$uid" 2>/dev/null | cut -d':' -f2 | awk '{print $1}' | tr '\n' ',' | sed 's/,$//'
}

################################################################################
# IPv6 Address Processing
################################################################################

# Convert IPv6 to standard format
normalize_ipv6() {
  local addr="$1"
  
  # Check if it's IPv4-mapped IPv6
  case "$addr" in
    *:ffff:*|*:FFFF:*)
      # Extract IPv4 part
      local ipv4_part=$(echo "$addr" | awk -F: '{print $NF}')
      if [ ${#ipv4_part} -gt 0 ]; then
        echo "ipv4-mapped:$ipv4_part"
      else
        echo "$addr"
      fi
      ;;
    *)
      echo "$addr"
      ;;
  esac
}

# Parse IPv6 endpoint
parse_ipv6_endpoint() {
  local endpoint="$1"
  local ip port
  
  # Handle IPv6 format: [ip]:port or just ip:port
  if [ "${endpoint#\[}" != "$endpoint" ]; then
    # Format: [ip]:port
    ip=$(echo "$endpoint" | sed 's/\[\(.*\)\]:.*/\1/')
    port=$(echo "$endpoint" | sed 's/.*\]:\(.*\)/\1/')
  else
    # Standard format
    ip=$(echo "$endpoint" | sed 's/\(.*\):\([^:]*\)$/\1/')
    port=$(echo "$endpoint" | sed 's/\(.*\):\([^:]*\)$/\2/')
  fi
  
  echo "$ip|$port"
}

################################################################################
# Connection State Tracking
################################################################################

track_connection_state() {
  local conn_id="$1"
  local state="$2"
  local local_ip="$3"
  local remote_ip="$4"
  local local_port="$5"
  local remote_port="$6"
  local protocol="$7"
  local uid="$8"
  
  local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  
  # Check if connection is new
  if ! grep -q "^$conn_id" "$PREV_STATE" 2>/dev/null; then
    echo "NEW|$timestamp|$protocol|$local_ip:$local_port|$remote_ip:$remote_port|$uid" >> "$TEMP_STATE"
  else
    # Check state change
    prev_state=$(grep "^$conn_id" "$PREV_STATE" 2>/dev/null | cut -d'|' -f2)
    if [ "$prev_state" != "$state" ]; then
      echo "CHANGED|$timestamp|$protocol|$local_ip:$local_port|$remote_ip:$remote_port|$uid|$prev_state->$state" >> "$TEMP_STATE"
    fi
  fi
  
  # Update connection state
  echo "$conn_id|$state|$timestamp|$protocol|$local_ip:$local_port|$remote_ip:$remote_port|$uid" >> "$TEMP_STATE"
}

################################################################################
# Inode/PID Resolution
################################################################################

resolve_inode_pid() {
  target_inode=$1
  target_uid=$2

  if [ -n "$target_inode" ] && [ "$target_inode" != "0" ]; then
    pid=$(awk -v ino="$target_inode" '$1 == ino {print $2; exit}' "$FD_MAP" 2>/dev/null)
    [ -n "$pid" ] && { echo "$pid"; return; }
  fi

  if [ -n "$target_uid" ] && [ "$target_uid" != "0" ]; then
    if [ "$target_uid" -ge 10000 ] 2>/dev/null; then
      app_user="u0_a$((target_uid - 10000))"
    else
      app_user="$target_uid"
    fi
    pid=$(ps -ef 2>/dev/null | awk -v u="$app_user" -v uid="$target_uid" 'NR > 1 && ($1 == u || $1 == uid) { print $2; exit }')
    [ -n "$pid" ] && { echo "$pid"; return; }
  fi

  echo "-"
}

################################################################################
# Statistics Collection
################################################################################

generate_stats() {
  local tcp_count=$(wc -l < "$TCP_LOG" 2>/dev/null || echo 0)
  local udp_count=$(wc -l < "$UDP_LOG" 2>/dev/null || echo 0)
  local unique_ips=$(cat "$TEMP_IPS" 2>/dev/null | cut -d' ' -f1 | sort -u | wc -l)
  local unique_domains=$(grep -o '|[^|]*|$' "$DNS_RESOLVED" 2>/dev/null | sort -u | wc -l)
  local new_connections=$(grep "^NEW" "$TEMP_STATE" 2>/dev/null | wc -l)
  
  {
    echo "===================="
    echo "NETWORK STATISTICS"
    echo "===================="
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "Connection Summary:"
    echo "  TCP Established: $tcp_count"
    echo "  UDP Active: $udp_count"
    echo "  Total Connections: $((tcp_count + udp_count))"
    echo ""
    echo "Unique IP Addresses: $unique_ips"
    echo "Unique Domains: $unique_domains"
    echo "New Connections This Cycle: $new_connections"
    echo ""
    echo "===================="
  } > "$STATS_SUMMARY"
  
  # Generate JSON stats
  {
    echo "{"
    echo '  "timestamp": "'$(date '+%Y-%m-%d %H:%M:%S')'\",'
    echo "  \"tcp_connections\": $tcp_count,"
    echo "  \"udp_connections\": $udp_count,"
    echo "  \"unique_ips\": $unique_ips,"
    echo "  \"unique_domains\": $unique_domains,"
    echo "  \"new_connections\": $new_connections"
    echo "}"
  } > "$STATS_JSON"
}

################################################################################
# Main Monitoring Loop
################################################################################

while true; do
  TIMESTAMP=$(date "+%H:%M:%S")
  DATE=$(date "+%Y-%m-%d")
  DATETIME=$(date "+%Y-%m-%d %H:%M:%S")
  
  # Ensure directories exist
  mkdir -p "$ACTIVITY_DIR" "$DOMAINS_DIR" "$STATS_DIR" 2>/dev/null
  
  # Clear activity logs for fresh data each cycle
  > "$CURRENT_LOG"
  > "$INTERFACES_LOG"
  > "$TCP_LOG"
  > "$UDP_LOG"
  > "$TEMP_STATE"
  > "$TEMP_IPS"
  > "$TEMP_CONNECTIONS"
  
  # Initialize CSV headers if new day
  if [ ! -f "$IP_HISTORY" ]; then
    echo "TIMESTAMP,IP,PORT,PROTOCOL,UID,PACKAGE,DOMAIN" > "$IP_HISTORY"
  fi
  
  if [ ! -f "$DOMAIN_HISTORY" ]; then
    echo "TIMESTAMP,IP,DOMAIN,PACKAGE,PORT,PROTOCOL,RESOLUTION_TIME" > "$DOMAIN_HISTORY"
  fi
  
  if [ ! -f "$DNS_RESOLVED" ]; then
    echo "TIMESTAMP,IP,DOMAIN,CONFIDENCE,SOURCE" > "$DNS_RESOLVED"
  fi
  
  if [ ! -f "$CONNECTION_STATE" ]; then
    echo "STATE_CHANGE,TIMESTAMP,PROTOCOL,LOCAL,REMOTE,UID,TRANSITION" > "$CONNECTION_STATE"
  fi

  rm -f "$TEMP_IPS"

  # Map socket inodes to active PIDs
  ls -l /proc/[0-9]*/fd 2>/dev/null | awk '
    /\/proc\/[0-9]+\/fd:/ { split($0, a, "/"); pid = a[3] }
    /socket:\[[0-9]+\]/ {
      if (match($0, /socket:\[[0-9]+\]/)) {
        s = substr($0, RSTART, RLENGTH)
        sub(/socket:\[/, "", s)
        sub(/\]/, "", s)
        print s, pid
      }
    }
  ' > "$FD_MAP"

  ################################################################################
  # Active Interfaces
  ################################################################################
  
  {
    echo "========================================="
    echo "ACTIVE NETWORK INTERFACES"
    echo "========================================="
    printf "%-12s %-14s %-14s\n" "INTERFACE" "RX-BYTES" "TX-BYTES"
    echo "-----------------------------------------"

    awk 'NR > 2 {
      iface=$1; sub(":", "", iface)
      if ($2 > 0 || $10 > 0) 
        printf "%-12s %-14s %-14s\n", iface, $2, $10
    }' /proc/net/dev
    
    echo ""
  } > "$INTERFACES_LOG"

  ################################################################################
  # TCP Connections (IPv4 + IPv6)
  ################################################################################
  
  TCP_OUT="/data/local/tmp/tcp_processed.tmp"

  awk -v tmp_file="$TEMP_IPS" '
    function hex2dec(h, i, v, c) {
      h = tolower(h); v = 0
      for (i = 1; i <= length(h); i++) {
        c = index("0123456789abcdef", substr(h, i, 1)) - 1
        if (c < 0) return 0
        v = v * 16 + c
      }
      return v
    }
    function ipv4(h) {
      return sprintf("%d.%d.%d.%d", hex2dec(substr(h,7,2)), hex2dec(substr(h,5,2)), hex2dec(substr(h,3,2)), hex2dec(substr(h,1,2)))
    }
    function parse_endpoint(ep,   colon_idx, raw_ip, raw_port, w3, w4) {
      colon_idx = index(ep, ":")
      if (colon_idx == 0) return "0.0.0.0:0"
      raw_ip = substr(ep, 1, colon_idx - 1)
      raw_port = substr(ep, colon_idx + 1)

      if (length(raw_ip) == 8) {
        return ipv4(raw_ip) ":" hex2dec(raw_port)
      } else if (length(raw_ip) == 32) {
        w3 = tolower(substr(raw_ip, 17, 8))
        w4 = substr(raw_ip, 25, 8)

        # Check for IPv4-mapped IPv6
        if (w3 == "0000ffff" || w3 == "ffff0000" || substr(raw_ip, 1, 16) == "0000000000000000") {
          if (w4 != "00000000" && w4 != "00000001") {
            return "IPv4-mapped:" ipv4(w4) ":" hex2dec(raw_port)
          }
        }

        # Localhost
        if (w4 == "0100007f" || w4 == "7f000001") {
          return "127.0.0.1:" hex2dec(raw_port)
        }

        # Format IPv6
        return sprintf("[%s:%s:%s:%s]:%s",
          substr(raw_ip,1,4), substr(raw_ip,5,4),
          substr(raw_ip,25,4), substr(raw_ip,29,4), hex2dec(raw_port))
      }
      return ep
    }

    $2 ~ /^[0-9A-Fa-f]+:[0-9A-Fa-f]+$/ {
      st = $4
      if (st != "01" && st != "0A") next

      state_str = (st == "01") ? "ESTAB" : "LISTEN"
      loc = parse_endpoint($2)
      rem = parse_endpoint($3)

      split(loc, l_a, ":"); lip = l_a[1]; lport = l_a[2]
      split(rem, r_a, ":"); rip = r_a[1]; rport = r_a[2]

      if (state_str == "ESTAB" && (lip == "127.0.0.1" || rip == "127.0.0.1" || rip == "0.0.0.0")) next
      if (lport == 5555 || lport == 5037 || rport == 5555 || rport == 5037) next

      print loc "|" rem "|TCP|" state_str "|" $8 "|" $10

      if (state_str == "ESTAB" && rip != "0.0.0.0")
        print rip " " rport " TCP " $8 " " $10 >> tmp_file
    }
  ' /proc/net/tcp /proc/net/tcp6 > "$TCP_OUT"

  {
    echo "========================================="
    echo "TCP CONNECTIONS (IPv4 + IPv6)"
    echo "========================================="
    printf "%-28s %-28s %-8s %-8s\n" "LOCAL" "REMOTE" "STATE" "UID"
    echo "-----------------------------------------"

    while IFS="|" read -r loc rem proto state uid inode; do
      [ -z "$loc" ] && continue
      printf "%-28s %-28s %-8s %-8s\n" "$loc" "$rem" "$state" "$uid"
    done < "$TCP_OUT"
    
    echo ""
  } > "$TCP_LOG"
  
  rm -f "$TCP_OUT"

  ################################################################################
  # UDP Connections (IPv4 + IPv6 - DNS, etc.)
  ################################################################################
  
  UDP_OUT="/data/local/tmp/udp_processed.tmp"

  awk -v tmp_file="$TEMP_IPS" '
    function hex2dec(h, i, v, c) {
      h = tolower(h); v = 0
      for (i = 1; i <= length(h); i++) {
        c = index("0123456789abcdef", substr(h, i, 1)) - 1
        if (c < 0) return 0
        v = v * 16 + c
      }
      return v
    }
    function ipv4(h) {
      return sprintf("%d.%d.%d.%d", hex2dec(substr(h,7,2)), hex2dec(substr(h,5,2)), hex2dec(substr(h,3,2)), hex2dec(substr(h,1,2)))
    }
    function parse_endpoint(ep,   colon_idx, raw_ip, raw_port, w3, w4) {
      colon_idx = index(ep, ":")
      if (colon_idx == 0) return "0.0.0.0:0"
      raw_ip = substr(ep, 1, colon_idx - 1)
      raw_port = substr(ep, colon_idx + 1)

      if (length(raw_ip) == 8) {
        return ipv4(raw_ip) ":" hex2dec(raw_port)
      } else if (length(raw_ip) == 32) {
        w3 = tolower(substr(raw_ip, 17, 8))
        w4 = substr(raw_ip, 25, 8)

        # Check for IPv4-mapped IPv6
        if (w3 == "0000ffff" || w3 == "ffff0000" || substr(raw_ip, 1, 16) == "0000000000000000") {
          if (w4 != "00000000" && w4 != "00000001") {
            return "IPv4-mapped:" ipv4(w4) ":" hex2dec(raw_port)
          }
        }

        # Localhost
        if (w4 == "0100007f" || w4 == "7f000001") {
          return "127.0.0.1:" hex2dec(raw_port)
        }

        # Format IPv6
        return sprintf("[%s:%s:%s:%s]:%s",
          substr(raw_ip,1,4), substr(raw_ip,5,4),
          substr(raw_ip,25,4), substr(raw_ip,29,4), hex2dec(raw_port))
      }
      return ep
    }

    $2 ~ /^[0-9A-Fa-f]+:[0-9A-Fa-f]+$/ {
      loc = parse_endpoint($2)
      rem = parse_endpoint($3)

      split(loc, l_a, ":"); lip = l_a[1]; lport = l_a[2]
      split(rem, r_a, ":"); rip = r_a[1]; rport = r_a[2]

      if (lip == "127.0.0.1" || rip == "127.0.0.1") next
      if (lport == 5555 || lport == 5037 || rport == 5555 || rport == 5037) next

      print loc "|" rem "|UDP|ACTIVE|" $8 "|" $10

      if (rip != "0.0.0.0" && rport != 0)
        print rip " " rport " UDP " $8 " " $10 >> tmp_file
    }
  ' /proc/net/udp /proc/net/udp6 > "$UDP_OUT"

  {
    echo "========================================="
    echo "UDP CONNECTIONS (IPv4 + IPv6)"
    echo "========================================="
    printf "%-28s %-28s %-8s %-8s\n" "LOCAL" "REMOTE" "TYPE" "UID"
    echo "-----------------------------------------"

    while IFS="|" read -r loc rem proto state uid inode; do
      [ -z "$loc" ] && continue
      printf "%-28s %-28s %-8s %-8s\n" "$loc" "$rem" "$proto" "$uid"
    done < "$UDP_OUT"
    
    echo ""
  } > "$UDP_LOG"
  
  rm -f "$UDP_OUT"

  ################################################################################
  # Main Activity Log (Consolidated - Current Only)
  ################################################################################
  
  {
    echo ""
    echo "========================================="
    echo "NETWORK ACTIVITY - $DATETIME"
    echo "========================================="
    echo ""
    cat "$INTERFACES_LOG"
    cat "$TCP_LOG"
    cat "$UDP_LOG"
    echo "========================================="
    echo "Updated: $DATETIME"
    echo "========================================="
  } > "$CURRENT_LOG"

  ################################################################################
  # IP History with Domain Resolution
  ################################################################################
  
  if [ -f "$TEMP_IPS" ]; then
    while read -r rip rport protocol uid inode; do
      [ -z "$rip" ] && continue
      
      # Check if already logged today
      if ! grep -q "^$TIMESTAMP.*${rip}" "$IP_HISTORY" 2>/dev/null; then
        pkg=$(resolve_uid "$uid")
        domain=$(get_domain "$rip")
        
        # Log to IP History (CSV)
        echo "$TIMESTAMP,$rip,$rport,$protocol,$uid,$pkg,$domain" >> "$IP_HISTORY"
        
        # Log to Domain History (CSV) - compact format
        echo "$TIMESTAMP,$rip,$domain,$pkg,$rport,$protocol,$(date +%s)" >> "$DOMAIN_HISTORY"
        
        # Log to resolved domains (CSV)
        echo "$TIMESTAMP,$rip,$domain,high,ip-api.com" >> "$DNS_RESOLVED"
      fi
    done < "$TEMP_IPS"
    rm -f "$TEMP_IPS"
  fi

  # Append connection state changes
  if [ -f "$TEMP_STATE" ]; then
    cat "$TEMP_STATE" >> "$CONNECTION_STATE"
    cp "$TEMP_STATE" "$PREV_STATE"
    rm -f "$TEMP_STATE"
  fi

  # Generate statistics
  generate_stats

  rm -f "$FD_MAP"
  
  # Wait before next cycle
  sleep 2
done

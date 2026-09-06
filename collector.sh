#!/system/bin/sh
################################################################################
# Network Collector - runs via `adb shell`, has /proc/net access but no
# working DNS tools. Dumps raw connection data to a shared queue file that
# the Termux-side resolver.sh will pick up and enrich with domain names.
################################################################################
BASE_DIR="/sdcard/Download/network-monitor"
ACTIVITY_DIR="$BASE_DIR/logs/activity"
QUEUE_DIR="$BASE_DIR/.queue"
QUEUE_FILE="$QUEUE_DIR/raw_ips.txt"
TCP_LOG="$ACTIVITY_DIR/tcp_connections.txt"
UDP_LOG="$ACTIVITY_DIR/udp_connections.txt"
IP_HISTORY="$BASE_DIR/ip_history_$(date +%Y-%m-%d).csv"
UID_MAP="$BASE_DIR/.cache/uid_map.csv"
mkdir -p "$ACTIVITY_DIR" "$QUEUE_DIR" "$BASE_DIR/.cache" 2>/dev/null
if [ ! -f "$IP_HISTORY" ]; then
  echo "TIMESTAMP,IP,PORT,PROTOCOL,UID,PACKAGE" > "$IP_HISTORY"
fi
# Build/refresh the UID -> package name map using `pm list packages -U`.
# No root needed - this is a normal Android shell command. Output looks like:
#   package:com.google.android.gm uid:10169
# We refresh periodically (not every cycle) since installed packages rarely
# change mid-session and `pm list` is relatively slow.
refresh_uid_map() {
  pm list packages -U 2>/dev/null | sed -n 's/^package:\(.*\) uid:\([0-9]*\)$/\2,\1/p' > "${UID_MAP}.tmp"
  if [ -s "${UID_MAP}.tmp" ]; then
    mv "${UID_MAP}.tmp" "$UID_MAP"
  fi
}
lookup_package() {
  local uid="$1"
  local pkg
  pkg=$(grep "^${uid}," "$UID_MAP" 2>/dev/null | cut -d',' -f2- | head -1)
  [ -z "$pkg" ] && pkg="uid_$uid"
  echo "$pkg"
}
# Build the map once at startup before the loop begins
refresh_uid_map
CYCLE_COUNT=0
# awk function block reused for both TCP and UDP parsing
AWK_FUNCS='
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
  # Returns "ip|port|is_mapped" - is_mapped is 1 or 0, never embedded in the ip field itself
  function parse_endpoint(ep,   colon_idx, raw_ip, raw_port, w3, w4, ip6) {
    colon_idx = index(ep, ":")
    if (colon_idx == 0) return "0.0.0.0|0|0"
    raw_ip = substr(ep, 1, colon_idx - 1)
    raw_port = substr(ep, colon_idx + 1)
    if (length(raw_ip) == 8) {
      return ipv4(raw_ip) "|" hex2dec(raw_port) "|0"
    } else if (length(raw_ip) == 32) {
      w3 = tolower(substr(raw_ip, 17, 8))
      w4 = substr(raw_ip, 25, 8)
      if (w3 == "0000ffff" || w3 == "ffff0000" || substr(raw_ip, 1, 16) == "0000000000000000") {
        if (w4 != "00000000" && w4 != "00000001") {
          return ipv4(w4) "|" hex2dec(raw_port) "|1"
        }
      }
      if (w4 == "0100007f" || w4 == "7f000001") {
        return "127.0.0.1|" hex2dec(raw_port) "|0"
      }
      ip6 = sprintf("%s:%s:%s:%s", substr(raw_ip,1,4), substr(raw_ip,5,4), substr(raw_ip,25,4), substr(raw_ip,29,4))
      return ip6 "|" hex2dec(raw_port) "|0"
    }
    return raw_ip "|0|0"
  }
'
while true; do
  TIMESTAMP=$(date "+%H:%M:%S")
  # Refresh the UID->package map every 12 cycles (~60s at 5s sleep) instead
  # of every loop, since `pm list packages` is slow and installed apps
  # rarely change mid-session.
  CYCLE_COUNT=$((CYCLE_COUNT + 1))
  if [ "$CYCLE_COUNT" -ge 12 ]; then
    refresh_uid_map
    CYCLE_COUNT=0
  fi
  > "$TCP_LOG"
  > "$UDP_LOG"
  > "$QUEUE_FILE"
  {
    echo "========================================="
    echo "TCP CONNECTIONS (IPv4 + IPv6)"
    echo "========================================="
    printf "%-20s %-20s %-8s %-8s\n" "LOCAL" "REMOTE" "STATE" "UID"
    echo "-----------------------------------------"
  } > "$TCP_LOG"
  awk -v qfile="$QUEUE_FILE" -v ts="$TIMESTAMP" "$AWK_FUNCS"'
    $2 ~ /^[0-9A-Fa-f]+:[0-9A-Fa-f]+$/ {
      st = $4
      if (st != "01" && st != "0A") next
      state_str = (st == "01") ? "ESTAB" : "LISTEN"
      split(parse_endpoint($2), l, "|")
      split(parse_endpoint($3), r, "|")
      lip=l[1]; lport=l[2]
      rip=r[1]; rport=r[2]
      if (state_str == "ESTAB" && (lip == "127.0.0.1" || rip == "127.0.0.1" || rip == "0.0.0.0")) next
      if (lport == 5555 || lport == 5037 || rport == 5555 || rport == 5037) next
      printf "%-20s %-20s %-8s %-8s\n", lip":"lport, rip":"rport, state_str, $8
      if (state_str == "ESTAB" && rip != "0.0.0.0")
        print rip "|" rport "|TCP|" $8 >> qfile
    }
  ' /proc/net/tcp /proc/net/tcp6 >> "$TCP_LOG" 2>/dev/null
  echo "" >> "$TCP_LOG"
  {
    echo "========================================="
    echo "UDP CONNECTIONS (IPv4 + IPv6)"
    echo "========================================="
    printf "%-20s %-20s %-8s %-8s\n" "LOCAL" "REMOTE" "TYPE" "UID"
    echo "-----------------------------------------"
  } > "$UDP_LOG"

  awk -v qfile="$QUEUE_FILE" "$AWK_FUNCS"'
    $2 ~ /^[0-9A-Fa-f]+:[0-9A-Fa-f]+$/ {
      split(parse_endpoint($2), l, "|")
      split(parse_endpoint($3), r, "|")
      lip=l[1]; lport=l[2]
      rip=r[1]; rport=r[2]

      if (lip == "127.0.0.1" || rip == "127.0.0.1") next
      if (lport == 5555 || lport == 5037 || rport == 5555 || rport == 5037) next

      printf "%-20s %-20s %-8s %-8s\n", lip":"lport, rip":"rport, "UDP", $8

      if (rip != "0.0.0.0" && rport != 0)
        print rip "|" rport "|UDP|" $8 >> qfile
    }
  ' /proc/net/udp /proc/net/udp6 >> "$UDP_LOG" 2>/dev/null
  echo "" >> "$UDP_LOG"

  # Append to permanent history CSV (dedup happens on the resolver side)
  if [ -f "$QUEUE_FILE" ]; then
    while IFS="|" read -r ip port proto uid; do
      [ -z "$ip" ] && continue
      pkg=$(lookup_package "$uid")
      echo "$TIMESTAMP,$ip,$port,$proto,$uid,$pkg" >> "$IP_HISTORY"
    done < "$QUEUE_FILE"
  fi

  sleep 5
done

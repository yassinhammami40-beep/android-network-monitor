#!/system/bin/sh

LOG="/sdcard/Download/traffic/network_activity.txt"
TMP_IPS="/data/local/tmp/current_ips.tmp"
CACHE_DIR="/data/local/tmp/.net_cache"
FD_MAP="/data/local/tmp/fd_inodes.tmp"
OUTPUT_DIR="/sdcard/Download/traffic"

# Startup cleanup routine
rm -rf "$CACHE_DIR" "$TMP_IPS" "$FD_MAP" /data/local/tmp/*_processed.tmp "$LOG"
mkdir -p "$OUTPUT_DIR" "$CACHE_DIR"

resolve_uid() {
  uid=$1
  cfile="$CACHE_DIR/u_$uid"
  if [ -f "$cfile" ]; then
    cat "$cfile"
  else
    pkg=$(pm list packages --uid "$uid" 2>/dev/null | cut -d':' -f2 | awk '{print $1}' | head -n1)
    [ -z "$pkg" ] && pkg="unknown"
    echo "$pkg" > "$cfile"
    echo "$pkg"
  fi
}

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

while true; do
  TIMESTAMP=$(date "+%H:%M:%S")
  TODAY=$(date "+%Y-%m-%d")
  IP_HISTORY="$OUTPUT_DIR/ips_24h_${TODAY}.txt"

  if [ ! -f "$IP_HISTORY" ]; then
    printf "%-12s %-18s %-8s %-8s %-8s %-35s\n" \
      "FIRST SEEN" "IP ADDRESS" "PORT" "UID" "PID" "PACKAGE" > "$IP_HISTORY"
  fi

  rm -f "$TMP_IPS"

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

  {
    echo "=== ACTIVE INTERFACES (/proc/net/dev) ==="
    printf "%-12s %-12s %-12s\n" "IFACE" "RX-BYTES" "TX-BYTES"
    awk 'NR > 2 {
      iface=$1; sub(":", "", iface)
      if ($2 > 0 || $10 > 0) printf "%-12s %-12s %-12s\n", iface, $2, $10
    }' /proc/net/dev

    echo ""
    echo "=== DETAILED TCP CONNECTIONS (/proc/net/tcp & tcp6) ==="
    printf "%-25s %-25s %-18s %-8s %-8s %-12s %-8s\n" \
      "LOCAL" "REMOTE" "TX/RX QUEUE" "STATE" "UID" "INODE" "PID"

    TCP_OUT="/data/local/tmp/tcp_processed.tmp"

    awk -v tmp_file="$TMP_IPS" '
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

          if (w3 == "0000ffff" || w3 == "ffff0000" || substr(raw_ip, 1, 16) == "0000000000000000") {
            if (w4 != "00000000" && w4 != "00000001") {
              return ipv4(w4) ":" hex2dec(raw_port)
            }
          }

          if (w4 == "0100007f" || w4 == "7f000001") {
            return "127.0.0.1:" hex2dec(raw_port)
          }

          return sprintf("%s:%s:%s:%s",
            substr(raw_ip,1,4), substr(raw_ip,5,4),
            substr(raw_ip,25,4), substr(raw_ip,29,4)) ":" hex2dec(raw_port)
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

        print loc "|" rem "|" $5 "|" state_str "|" $8 "|" $10

        if (state_str == "ESTAB" && rip != "0.0.0.0")
          print rip " " rport " " $8 " " $10 >> tmp_file
      }
    ' /proc/net/tcp /proc/net/tcp6 > "$TCP_OUT"

    while IFS="|" read -r loc rem queue state uid inode; do
      [ -z "$loc" ] && continue
      pid=$(resolve_inode_pid "$inode" "$uid")
      printf "%-25s %-25s %-18s %-8s %-8s %-12s %-8s\n" "$loc" "$rem" "$queue" "$state" "$uid" "$inode" "$pid"
    done < "$TCP_OUT"
    rm -f "$TCP_OUT"

    echo ""
    echo "=== DETAILED UDP SOCKETS (/proc/net/udp & udp6) ==="
    printf "%-25s %-25s %-18s %-8s %-8s %-12s %-8s\n" \
      "LOCAL" "REMOTE" "TX/RX QUEUE" "STATE" "UID" "INODE" "PID"

    UDP_OUT="/data/local/tmp/udp_processed.tmp"

    awk -v tmp_file="$TMP_IPS" '
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

          if (w3 == "0000ffff" || w3 == "ffff0000" || substr(raw_ip, 1, 16) == "0000000000000000") {
            if (w4 != "00000000" && w4 != "00000001") {
              return ipv4(w4) ":" hex2dec(raw_port)
            }
          }

          if (w4 == "0100007f" || w4 == "7f000001") {
            return "127.0.0.1:" hex2dec(raw_port)
          }

          return sprintf("%s:%s:%s:%s",
            substr(raw_ip,1,4), substr(raw_ip,5,4),
            substr(raw_ip,25,4), substr(raw_ip,29,4)) ":" hex2dec(raw_port)
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

        print loc "|" rem "|" $5 "|UDP|" $8 "|" $10

        if (rip != "0.0.0.0" && rport != 0)
          print rip " " rport " " $8 " " $10 >> tmp_file
      }
    ' /proc/net/udp /proc/net/udp6 > "$UDP_OUT"

    while IFS="|" read -r loc rem queue state uid inode; do
      [ -z "$loc" ] && continue
      pid=$(resolve_inode_pid "$inode" "$uid")
      printf "%-25s %-25s %-18s %-8s %-8s %-12s %-8s\n" "$loc" "$rem" "$queue" "$state" "$uid" "$inode" "$pid"
    done < "$UDP_OUT"
    rm -f "$UDP_OUT"

  } > "$LOG"

  # Daily IP History append
  if [ -f "$TMP_IPS" ]; then
    while read -r rip rport uid inode; do
      [ -z "$rip" ] && continue
      if ! grep -qE "[[:space:]]${rip}[[:space:]]+${rport}[[:space:]]" "$IP_HISTORY" 2>/dev/null; then
        pkg=$(resolve_uid "$uid")
        pid=$(resolve_inode_pid "$inode" "$uid")
        printf "%-12s %-18s %-8s %-8s %-8s %-35s\n" "$TIMESTAMP" "$rip" "$rport" "$uid" "$pid" "$pkg" >> "$IP_HISTORY"
      fi
    done < "$TMP_IPS"
    rm -f "$TMP_IPS"
  fi

  rm -f "$FD_MAP"
  sleep 2
done


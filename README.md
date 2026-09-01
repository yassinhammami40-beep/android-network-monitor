# Android Network Monitor v2.0

> Advanced network analysis tool for Android with full IPv4/IPv6 support, DNS correlation, connection lifecycle tracking, and multi-format output (TXT/CSV/JSON).

## 🎯 Features

### Core Capabilities
- ✅ **Full IPv4 & IPv6 Support** - Monitors both `tcp/tcp6` and `udp/udp6` sockets
- ✅ **IPv4-Mapped IPv6 Handling** - Automatically detects and converts `::ffff:x.x.x.x` addresses
- ✅ **Connection Lifecycle Tracking** - Detects NEW, ACTIVE, and CLOSED connections
- ✅ **DNS Correlation** - Reverse DNS lookups with intelligent caching
- ✅ **Multi-UID Resolution** - Handles Android services sharing UIDs across multiple processes
- ✅ **Multiple Output Formats** - TXT (browser-friendly), CSV, and JSON outputs
- ✅ **Real-time Statistics** - Connection counts, unique IPs, and domain metrics
- ✅ **Clean Logging** - Organized folder structure with separate concerns

### Network Traffic Types
- **TCP Connections** - ESTABLISHED and LISTEN states (IPv4 & IPv6)
- **UDP Sockets** - Active UDP ports including DNS traffic (IPv4 & IPv6)
- **Interface Statistics** - RX/TX byte counters per network interface
- **DNS Resolution** - Reverse DNS with fallback to "unknown"

---

## 📁 Directory Structure

```
/sdcard/Download/network-monitor/
├── logs/
│   ├── activity/
│   │   ├── current.txt                 # Main consolidated activity log
│   │   ├── interfaces.txt              # Network interface stats
│   │   ├── tcp_connections.txt         # TCP connections (IPv4 + IPv6)
│   │   ├── udp_connections.txt         # UDP connections (IPv4 + IPv6)
│   │   └── connection_state.csv        # Connection state changes
│   ├── monitor.log                     # Monitor status & errors
│   └── (old activity logs auto-deleted after 24h)
├── domains/
│   ├── resolved_domains.csv            # Global DNS cache (CSV)
│   ├── domain_history_YYYY-MM-DD.csv   # Daily domain mapping
│   └── domain_correlation.csv          # IP-to-Domain correlation
├── stats/
│   ├── summary_YYYY-MM-DD.txt          # Daily statistics summary
│   └── stats_YYYY-MM-DD.json           # JSON metrics
├── ip_history_YYYY-MM-DD.csv           # Daily IP tracking (persistent)
└── .cache/
    └── dns_cache.db                    # DNS resolution cache
```

---

## 🔧 Technical Architecture

### Data Flow Diagram

```
                        ╔═════════════════════════╗
                        ║   /proc/net/tcp*        ║
                        ║   (TCP/UDP Socket Data) ║
                        ╚═════════════╤═════════╝
                                      │
                    ┌─────────────────┼─────────────────┐
                    │                 │                 │
                    ▼                 ▼                 ▼
            ╔─────────────╗  ╔──────────────╗  ╔──────────────╗
            ║Local IP:Port║  ║Remote IP:Port║  ║State & UID   ║
            ║             ║  ║               ║  ║              ║
            ╚─────┬───────╝  ╚────┬──────────╝  ╚────┬─────────╝
                  │               │                  │
                  └───────────────┼──────────────────┘
                                  │
                                  ▼
                        ╔═════════════════════════╗
                        ║  Parse Hex Endpoints    ║
                        ║  - IPv4 & IPv6 Support  ║
                        ║  - Detect IPv4-mapped   ║
                        ║  - Format: IP:PORT      ║
                        ╚═════════════╤═════════╝
                                      │
                    ┌─────────────────┼─────────────────┐
                    │                 │                 │
                    ▼                 ▼                 ▼
            ╔─────────────╗  ╔──────────────╗  ╔──────────────╗
            ║ Local Addr  ║  ║  Remote IP   ║  ║    State     ║
            ║ Local Port  ║  ║  Remote Port ║  ║(ESTAB/LISTEN)║
            ╚──────┬──────╝  ╚──────┬───────╝  ╚──────┬────────╝
                   │                │               │
                   └────────────────┼───────────────┘
                                    │
                                    ▼
                        ╔═════════════════════════╗
                        ║ Extract Socket Inode    ║
                        ║ from /proc/net/tcp*     ║
                        ╚═════════════╤═════════╝
                                      │
                                      ▼
                        ╔═════════════════════════╗
                        ║ Search /proc/<PID>/fd/  ║
                        ║ Match inode with:       ║
                        ║ socket:[<inode>]        ║
                        ╚═════════════╤═════════╝
                                      │
                                      ▼
                        ╔═════════════════════════╗
                        ║ Extract PID Owner       ║
                        ║ From process listing    ║
                        ╚═════════════╤═════════╝
                                      │
                                      ▼
                        ╔═════════════════════════╗
                        ║ Extract UID from PID    ║
                        ║ Via /proc/<PID>/stat    ║
                        ║ or ps output            ║
                        ╚═════════════╤═════════╝
                                      │
                                      ▼
                        ╔═════════════════════════╗
                        ║ Resolve Package Name    ║
                        ║ pm list packages        ║
                        ║ --uid <UID>             ║
                        ║ (with caching)          ║
                        ╚═════════════╤═════════╝
                                      │
                                      ▼
                        ╔═════════════════════════╗
                        ║ Resolve Reverse DNS     ║
                        ║ Remote IP → Domain      ║
                        ║ (ip-api.com with TTL)   ║
                        ║ Cache result            ║
                        ╚═════════════╤═════════╝
                                      │
                    ┌─────────────────┼─────────────────┐
                    │                 │                 │
                    ▼                 ▼                 ▼
            ╔────────────╗    ╔──────────────╗  ╔──────────────╗
            ║  TXT Output║    ║CSV Analysis  ║  ║JSON Metrics  ║
            ║(Browser)   │    │(Persistent)  ║  │(Statistics)  ║
            ╚────────────╝    ╚──────────────╝  ╚──────────────╝
```

### 1. IPv6 Support

The monitor handles all IPv6 variants:

```
Standard IPv6:     [2001:db8::1]:443
IPv4-mapped:       [::ffff:142.250.73.67]:443  → Converted to: 142.250.73.67:443
Link-local:        fe80::1                       → Skipped (local-only)
Multicast:         ff00::1                       → Skipped
```

**IPv4-mapped Detection** (in `/proc/net/tcp6`):
```
Raw:     0000000000000000ffff0000aef04943
Parsed:  ::ffff:174.240.73.67
Result:  IPv4-mapped:174.240.73.67:443
```

### 2. Connection Lifecycle Tracking

Connections are tracked across monitoring cycles:

```
State Transitions:
  ┌─────────────┐
  │   NEW       │ (First seen in this cycle)
  └──────┬──────┘
         │
  ┌──────▼──────────┐
  │    ACTIVE       │ (ESTABLISHED state)
  └──────┬──────────┘
         │
  ┌──────▼──────────┐
  │   CLOSED        │ (Removed from /proc/net)
  └─────────────────┘
```

**State Tracking Files:**
- `connection_state.csv` - NEW/CHANGED/CLOSED events
- `prev_state.tmp` - Previous cycle's connection snapshot
- Connection ID = `protocol:local_ip:local_port:remote_ip:remote_port:uid`

### 3. DNS Resolution Strategy

**Multi-layer DNS Correlation:**

```
Layer 1: In-Memory Cache
  → Check /data/local/tmp/.net_monitor_cache/dns_cache.db
  → Instant response for repeat queries

Layer 2: ip-api.com API
  → Timeout: 3 seconds (configurable)
  → Reverse DNS lookup
  → Extract main domain (pkg.github.com → github.com)
  → Cache result for future cycles

Layer 3: Fallback
  → Mark as "unknown" if resolution fails
  → Still cache to prevent retry loops
```

**DNS Cache Format:**
```
IP=DOMAIN
142.250.73.67=google.com
23.197.84.90=akamaitechnologies.com
71.18.223.7=unknown
```

**Confidence Levels in CSV:**
```
TIMESTAMP,IP,DOMAIN,CONFIDENCE,SOURCE
22:36:16,142.250.73.67,google.com,high,ip-api.com
22:36:16,71.18.223.7,unknown,medium,timeout
```

### 4. UID to Package Resolution

**Challenge:** Android apps can:
- Share UIDs (e.g., system services)
- Spawn multiple processes
- Run under different user IDs

**Solution:**
```bash
# Get primary package for UID
resolve_uid(uid) → pm list packages --uid UID

# Get all packages for UID
get_all_packages_for_uid(uid) → [pkg1, pkg2, pkg3]

# Cache results
~/.net_monitor_cache/u_<UID> → package_name
```

**UID Ranges:**
```
0-1000:           System UIDs
1000-9999:        Reserved
10000+:           App UIDs (u0_a0 = 10000, u0_a1 = 10001, etc.)
```

### 5. Output Formats

#### TXT (Browser-Friendly)
```
=========================================
ACTIVE NETWORK INTERFACES
=========================================
INTERFACE    RX-BYTES       TX-BYTES
-----------------------------------------
wlan0        674385221      699119
lo           12345          12345

=========================================
TCP CONNECTIONS (IPv4 + IPv6)
=========================================
LOCAL                      REMOTE                     STATE    UID
-----------------------------------------
10.97.178.91:45684         142.250.141.188:443        ESTAB    10262
[2001:db8::1]:5000         [2001:db8::2]:443          ESTAB    10000
```

#### CSV (Analysis-Ready)
```
TIMESTAMP,IP,PORT,PROTOCOL,UID,PACKAGE,DOMAIN
22:36:16,142.250.73.67,443,TCP,10262,com.instagram,instagram.com
22:36:16,142.251.215.234,53,UDP,10262,com.instagram,google-dns.com
```

#### JSON (Machine-Readable)
```json
{
  "timestamp": "2026-08-31 22:36:16",
  "tcp_connections": 12,
  "udp_connections": 8,
  "unique_ips": 24,
  "unique_domains": 18,
  "new_connections": 3
}
```

---

## 🚀 Installation & Usage

### Prerequisites
```bash
# Required tools
- netstat or ss
- awk, sed, grep
- nc (netcat)
- Android shell access (ADB or Termux)

# Permissions
- Read access to /proc/net/tcp, /proc/net/udp
- ADB shell or Termux with proper permissions
```

### Installation

```bash
# Clone repository
git clone https://github.com/yassinhammami40-beep/android-network-monitor.git
cd android-network-monitor

# Make executable
chmod +x network_monitor.sh

# Run (via ADB)
adb shell "cat > /data/local/tmp/network_monitor.sh < network_monitor.sh && sh /data/local/tmp/network_monitor.sh"

# OR via Termux
chmod +x network_monitor.sh
./network_monitor.sh
```

### File Access (After Running)

```bash
# View current activity (real-time)
cat /sdcard/Download/network-monitor/logs/activity/current.txt

# View TCP connections
cat /sdcard/Download/network-monitor/logs/activity/tcp_connections.txt

# View domain history (CSV - import to Excel/Sheets)
cat /sdcard/Download/network-monitor/domains/domain_history_2026-08-31.csv

# View statistics
cat /sdcard/Download/network-monitor/stats/summary_2026-08-31.txt

# Parse JSON stats
cat /sdcard/Download/network-monitor/stats/stats_2026-08-31.json | jq
```

### Browser Access
```
Open any file manager → Navigate to /sdcard/Download/network-monitor/
Click on .txt or .csv files to view in browser
```

---

## 📈 Use Cases

### 1. Privacy Analysis
```bash
# Find all domains an app connects to
grep "com.instagram" /sdcard/Download/network-monitor/domains/domain_history_*.csv
```

### 2. Malware Detection
```bash
# Identify unusual IPs without DNS resolution
grep ",unknown," /sdcard/Download/network-monitor/domains/resolved_domains.csv

# Track new connections
grep "^NEW" /sdcard/Download/network-monitor/logs/activity/connection_state.csv
```

### 3. Network Debugging
```bash
# Check IPv6 usage
grep "IPv6\|::" /sdcard/Download/network-monitor/logs/activity/tcp_connections.txt

# Monitor specific app's traffic
grep "com.whatsapp" /sdcard/Download/network-monitor/ip_history_*.csv
```

### 4. Performance Analysis
```bash
# Export JSON stats to analyze trends
tail -1 /sdcard/Download/network-monitor/stats/stats_*.json
```

---

## 🔐 Security Considerations

### Data Sensitivity
- **Logged Data**: IP addresses, ports, domains, package names
- **Storage**: `/sdcard/Download/` is typically readable by all apps
- **Recommendation**: Use a secure folder or encrypted storage

### Privacy
- DNS queries to ip-api.com are external
- Consider local DNS resolution alternatives
- Local caching reduces external queries

### Permissions
- Requires `/proc/net/` read access (system-level)
- Monitor runs as shell user
- Limited cross-app isolation possible

---

## 🐛 Troubleshooting

### No Output
```bash
# Check if running
ps aux | grep network_monitor.sh

# Check permissions
ls -la /sdcard/Download/network-monitor/

# Check errors
cat /sdcard/Download/network-monitor/logs/monitor.log
```

### DNS Resolution Fails
```bash
# Test manually
echo -e "GET /json/142.250.73.67?fields=reverse HTTP/1.1\r\nHost: ip-api.com\r\nConnection: close\r\n\r\n" | nc ip-api.com 80

# Check cache
cat /data/local/tmp/.net_monitor_cache/dns_cache.db
```

### Too Many "unknown" Domains
- May indicate network issues
- Check internet connectivity
- ip-api.com might be rate-limited (max ~45 req/min)
- Local caching helps but new IPs will be slow

### IPv6 Not Showing
```bash
# Check if IPv6 is available
cat /proc/net/tcp6 | head

# Verify parsing
# IPv6 addresses should appear as [xxxx:xxxx...]:port
```

---

## 📋 Output Specifications

### connection_state.csv Format
```
STATE_CHANGE,TIMESTAMP,PROTOCOL,LOCAL,REMOTE,UID,TRANSITION
NEW,2026-08-31 22:36:16,TCP,10.97.178.91:45684,142.250.141.188:443,10262
CHANGED,2026-08-31 22:36:20,TCP,10.97.178.91:45684,142.250.141.188:443,10262,LISTEN->ESTAB
CLOSED,2026-08-31 22:37:00,TCP,10.97.178.91:45684,142.250.141.188:443,10262
```

### domain_history_YYYY-MM-DD.csv Format
```
TIMESTAMP,IP,DOMAIN,PACKAGE,PORT,PROTOCOL,RESOLUTION_TIME
22:36:16,142.250.73.67,google.com,com.google.android.apps,443,TCP,1724087776
22:36:17,23.197.84.90,akamaitechnologies.com,com.instagram,443,TCP,1724087777
```

### ip_history_YYYY-MM-DD.csv Format
```
TIMESTAMP,IP,PORT,PROTOCOL,UID,PACKAGE,DOMAIN
22:36:16,142.250.73.67,443,TCP,10262,com.instagram,instagram.com
22:36:16,142.251.215.234,53,UDP,10262,com.instagram,google-dns.com
```

---

## 🔄 Cycle Behavior

Each monitoring cycle (2 seconds):

1. **Parse Network State** - Read `/proc/net/*` files
2. **Detect Changes** - Compare with previous cycle
3. **Resolve Names** - Query DNS cache or ip-api.com
4. **Map Packages** - Resolve UID to app package
5. **Log Output** - Write to TXT/CSV/JSON files
6. **Update Statistics** - Calculate metrics
7. **Cleanup** - Remove old temp files
8. **Sleep** - Wait 2 seconds before next cycle

---

## 📝 Configuration

Edit the script to customize:

```bash
# DNS timeout (seconds)
RESOLUTION_TIMEOUT=3

# DNS cache TTL (seconds)
DNS_CACHE_TTL=3600

# Monitoring cycle (seconds)
sleep 2

# Output directories
BASE_DIR="/sdcard/Download/network-monitor"
```

---

## 🤝 Contributing

### Report Issues
- Include `/sdcard/Download/network-monitor/logs/monitor.log`
- Share sample output from `current.txt`
- Specify Android version and device model

### Improvements
- IPv6 edge cases
- DNS resolution fallbacks
- Performance optimizations
- Additional output formats (PCAP, SQLite)

---

## 📜 License

MIT License - See LICENSE file

---

## 🙋 FAQ

**Q: Is this tool detectable by apps?**
A: Yes, apps can detect network monitoring via various methods. Use responsibly.

**Q: Does it work offline?**
A: Yes, for local IP tracking. DNS resolution requires internet for external IPs.

**Q: Can I use it without root?**
A: Limited functionality. Requires read access to `/proc/net/`.

**Q: What's the performance impact?**
A: Minimal (~2-5% CPU per cycle). Adjust sleep interval to reduce overhead.

**Q: Does it capture packet data?**
A: No, only connection metadata from `/proc/net/`. For packet capture, use tcpdump.

---

## 📞 Support

For issues and questions:
- GitHub Issues: [Android Network Monitor Issues](https://github.com/yassinhammami40-beep/android-network-monitor/issues)
- Email: yassinhammami40@gmail.com

---

**Last Updated:** 2026-08-31  
**Version:** 2.0  
**Status:** Active Development

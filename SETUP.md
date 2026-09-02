># Android Network Monitor v2.1 - Termux Setup Guide

## Overview

**Android Network Monitor v2.1** is a comprehensive shell-based network analysis tool optimized for Android devices via ADB or Termux. It provides real-time TCP/UDP connection tracking, DNS resolution, interface monitoring, and detailed network statistics with full IPv4/IPv6 support.

### Key Features
- ✅ Full IPv4 and IPv6 support (including IPv4-mapped IPv6)
- ✅ Real-time TCP/UDP connection tracking
- ✅ DNS resolution with intelligent fallback chain
- ✅ Connection state lifecycle tracking (NEW, ACTIVE, CLOSED)
- ✅ Multiple output formats (TXT, CSV, JSON)
- ✅ Seamless Termux binary integration
- ✅ Robust error handling and safe file operations

---

## Prerequisites

### Device Requirements
- Android device with ADB access or Termux installed
- Minimum 50 MB free storage in `/sdcard/Download/`
- Root access (recommended for full network access)

### On Your Android Device

#### Step 1: Install Termux (Recommended)
Download from **F-Droid** or **GitHub Releases** (avoid Play Store for latest version):
- [F-Droid: Termux](https://f-droid.org/packages/com.termux/)
- [GitHub: Termux Releases](https://github.com/termux/termux-app/releases)

#### Step 2: Update Package Manager
Open Termux and run:
```bash
pkg update
pkg upgrade -y
```

#### Step 3: Install Required Tools
```bash
pkg install -y bind-tools curl jq awk
```

**What each tool does:**
| Tool | Purpose | Alternative |
|------|---------|-------------|
| `bind-tools` | Provides `dig` for DNS lookups | Required for Method 1 (fastest) |
| `curl` | HTTP client for API queries | Required for Method 2 (reliable) |
| `jq` | JSON parser for API responses | Paired with `curl` |
| `awk` | Text processing (usually pre-installed) | Core utility |

#### Step 4 (Optional): Install Busybox for Legacy Fallback
```bash
pkg install -y busybox
```
Provides `nc` (netcat) for fallback DNS resolution if other methods fail.

---

## Installation & Deployment

### Option A: Via ADB (Recommended for Non-Root Setups)

#### 1. Push Script to Device
```bash
# On your PC/Mac with ADB installed
adb push network_monitor.sh /sdcard/Download/
adb shell chmod +x /sdcard/Download/network_monitor.sh
```

#### 2. Verify Installation
```bash
adb shell ls -lah /sdcard/Download/network_monitor.sh
```

#### 3. Run from ADB Shell
```bash
adb shell /sdcard/Download/network_monitor.sh
```

### Option B: Via Termux (Recommended for Root Setups)

#### 1. Copy Script into Termux
```bash
# In Termux terminal
cp /sdcard/Download/network_monitor.sh ~/
chmod +x ~/network_monitor.sh
```

#### 2. Run Inside Termux
```bash
bash ~/network_monitor.sh
```

Or with explicit Termux shell:
```bash
termux-shell ~/network_monitor.sh
```

---

## DNS Resolution Fallback Chain

The script implements an intelligent 4-method fallback chain for reverse DNS lookups:

### Method 1: `dig` (Fastest - Requires: `bind-tools`)
```bash
dig +short -x <IP_ADDRESS>
```
- **Speed:** ~100-200ms per lookup
- **Accuracy:** Native DNS queries
- **Dependencies:** `pkg install bind-tools`

### Method 2: `curl` + `jq` (Reliable - Requires: `curl`, `jq`)
```bash
curl -s "http://ip-api.com/json/<IP_ADDRESS>?fields=reverse" | jq -r '.reverse'
```
- **Speed:** ~500-1000ms per lookup
- **Accuracy:** IP geolocation API
- **Dependencies:** `pkg install curl jq`

### Method 3: `nc` (Legacy - Requires: `busybox`)
```bash
echo -e 'GET /json/<IP_ADDRESS>?fields=reverse HTTP/1.1\r\nHost: ip-api.com\r\n\r\n' | nc -w 2 ip-api.com 80
```
- **Speed:** ~1000-2000ms per lookup
- **Accuracy:** HTTP fallback parsing
- **Dependencies:** `pkg install busybox`

### Method 4: Cache Fallback (No Network Required)
- Returns cached results from previous resolutions
- Defaults to `"unknown"` if not in cache

**Auto-Detection:** The script automatically detects available binaries and uses the fastest available method.

---

## Output Locations

All logs and data are stored in `/sdcard/Download/network-monitor/`:

```
network-monitor/
├── logs/
│   ├── monitor.log                    # Startup/runtime logs
│   └── activity/
│       ├── current.txt                # Live network activity (refreshed every 2s)
│       ├── interfaces.txt             # Active network interfaces
│       ├── tcp_connections.txt        # TCP sessions (IPv4 + IPv6)
│       ├── udp_connections.txt        # UDP sessions (IPv4 + IPv6)
│       └── connection_state.csv       # Connection lifecycle changes
├── domains/
│   ├── resolved_domains.csv           # All DNS resolutions
│   ├── domain_history_YYYY-MM-DD.csv  # Daily domain resolution history
│   └── domain_correlation.csv         # Domain-to-IP mappings
├── stats/
│   ├── summary_YYYY-MM-DD.txt         # Daily statistics summary
│   └── stats_YYYY-MM-DD.json          # Daily JSON statistics
├── ip_history_YYYY-MM-DD.csv          # Daily IP connection history
└── .cache/
    ├── dns_cache.db                   # Cached DNS lookups (TTL: 1 hour)
    ├── fd_inodes.tmp                  # Socket-to-PID mappings
    ├── current_ips.tmp                # IPs seen this cycle
    ├── connection_state.tmp           # State changes (temp)
    └── u_<UID>                        # Cached package-to-UID mappings
```

### Output File Formats

#### CSV Files (Comma-Separated Values)
```csv
# resolved_domains.csv
TIMESTAMP,IP,DOMAIN,CONFIDENCE,SOURCE
2026-09-02 14:30:15,8.8.8.8,google-dns-a.google.com,high,api

# ip_history_YYYY-MM-DD.csv
TIMESTAMP,IP,PORT,PROTOCOL,UID,PACKAGE,DOMAIN
14:30:15,8.8.8.8,53,TCP,10123,com.example.app,google-dns-a.google.com
```

#### JSON Format
```json
{
  "timestamp": "2026-09-02 14:30:15",
  "tcp_connections": 12,
  "udp_connections": 5,
  "unique_ips": 18,
  "unique_domains": 8,
  "new_connections": 2
}
```

#### TXT Format (Browser-Compatible)
```
=========================================
NETWORK ACTIVITY - 2026-09-02 14:30:15
=========================================

ACTIVE NETWORK INTERFACES
-----------------------------------------
INTERFACE      RX-BYTES       TX-BYTES
wlan0          1024000000     512000000

TCP CONNECTIONS (IPv4 + IPv6)
-----------------------------------------
LOCAL                       REMOTE                      STATE    UID
192.168.1.100:54321         8.8.8.8:443                 ESTAB    10123
[::1]:8080                  [2001:4860:4860::8888]:53   ESTAB    0
```

---

## Troubleshooting

### ❌ "Permission denied" Errors
**Problem:** Script cannot be executed
```bash
adb shell permission denied: /sdcard/Download/network_monitor.sh
```

**Solution:**
```bash
# Ensure script is executable
adb shell chmod +x /sdcard/Download/network_monitor.sh

# Or run with explicit shell
adb shell sh /sdcard/Download/network_monitor.sh
adb shell bash /sdcard/Download/network_monitor.sh
```

---

### ❌ DNS Resolution Not Working
**Problem:** Domains show as "unknown"
```csv
2026-09-02 14:30:15,8.8.8.8,unknown,high,api
```

**Solution:**
1. **Check internet connectivity:**
   ```bash
   adb shell ping -c 1 8.8.8.8
   ```

2. **Verify Termux tools installed:**
   ```bash
   adb shell command -v dig curl jq nc
   ```

3. **Manual install missing tools:**
   ```bash
   pkg install -y bind-tools curl jq busybox
   ```

4. **Test DNS resolution manually:**
   ```bash
   # Test dig
   adb shell dig +short -x 8.8.8.8
   
   # Test curl + jq
   adb shell curl -s "http://ip-api.com/json/8.8.8.8?fields=reverse" | jq -r '.reverse'
   ```

---

### ❌ Script Crashes on Startup
**Problem:** 
```bash
/system/bin/sh: syntax error near unexpected token...
```

**Solution:**
1. **Run with explicit Bash:**
   ```bash
   adb shell bash /sdcard/Download/network_monitor.sh
   ```

2. **Check script encoding (must be UNIX LF):**
   ```bash
   # On your PC, convert to UNIX line endings
   dos2unix network_monitor.sh  # or use sed
   sed -i 's/\r$//' network_monitor.sh
   ```

3. **Check logs:**
   ```bash
   adb shell cat /sdcard/Download/network-monitor/logs/monitor.log
   ```

---

### ❌ "/data/local/tmp/ Permission denied"
**Problem:** Script cannot write to temporary files
```bash
Error writing to /data/local/tmp/...
```

**Solution:** 
Script v2.1 now uses `$BASE_DIR/.cache/` (writable by all users) instead of `/data/local/tmp/`. This is **automatic** — no action needed.

Verify cache directory is created:
```bash
adb shell ls -la /sdcard/Download/network-monitor/.cache/
```

---

### ❌ High Memory/CPU Usage
**Problem:** Script consumes excessive resources

**Solution:**
1. **Reduce monitoring frequency** (edit line 598):
   ```bash
   sleep 2    # Change to: sleep 5 or sleep 10
   ```

2. **Disable IPv6 monitoring** (comment out lines 524-541):
   ```bash
   # awk ... /proc/net/udp6 > "$UDP_OUT"
   ```

3. **Reduce DNS cache retention** (edit line 48):
   ```bash
   DNS_CACHE_TTL=3600    # Change to: 600 (10 minutes)
   ```

---

## Running the Script

### Start Monitoring
```bash
# Via ADB
adb shell /sdcard/Download/network_monitor.sh

# Via Termux
bash ~/network_monitor.sh

# With nohup (runs in background)
adb shell nohup /sdcard/Download/network_monitor.sh > /sdcard/Download/network-monitor/logs/monitor.log 2>&1 &
```

### View Live Activity
```bash
# Real-time (updates every 2 seconds)
adb shell cat /sdcard/Download/network-monitor/logs/activity/current.txt

# Continuous monitoring
adb shell tail -f /sdcard/Download/network-monitor/logs/activity/current.txt
```

### Analyze Logs
```bash
# View TCP connections
adb shell cat /sdcard/Download/network-monitor/logs/activity/tcp_connections.txt

# View DNS resolutions (CSV)
adb shell cat /sdcard/Download/network-monitor/domains/resolved_domains.csv

# View daily statistics
adb shell cat /sdcard/Download/network-monitor/stats/summary_$(date +%Y-%m-%d).txt

# Export to JSON for parsing
adb shell cat /sdcard/Download/network-monitor/stats/stats_$(date +%Y-%m-%d).json | jq .
```

### Stop Monitoring
```bash
# Find and kill the process
adb shell ps | grep network_monitor.sh
adb shell kill <PID>

# Or (if running with nohup)
adb shell pkill -f network_monitor.sh
```

---

## Advanced Configuration

### Adjust Monitoring Interval
Edit line 598 in `network_monitor.sh`:
```bash
sleep 2    # Current: 2 seconds
sleep 5    # Lighter load: 5 seconds
sleep 10   # Very light: 10 seconds
```

### Change Base Directory
Edit line 15:
```bash
BASE_DIR="/sdcard/Download/network-monitor"    # Current
BASE_DIR="/storage/emulated/0/network-monitor" # Alternative
BASE_DIR="/data/local/tmp/network-monitor"     # Requires root
```

### Disable DNS Resolution
Comment out lines 572-581 in the main loop:
```bash
# pkg=$(resolve_uid "$uid")
# domain=$(get_domain "$rip")
```

### Filter Specific Ports
Edit lines 432 and 517 (TCP/UDP filtering):
```bash
if (lport == 5555 || lport == 5037 || rport == 5555 || rport == 5037) next
# Add more ports: || lport == 3306 || rport == 3306
```

---

## Example Use Cases

### 1. Monitor App Network Activity
```bash
# Push and run script
adb push network_monitor.sh /sdcard/Download/
adb shell chmod +x /sdcard/Download/network_monitor.sh
adb shell /sdcard/Download/network_monitor.sh &

# Open your app, wait 30 seconds
# View connected IPs
adb shell cat /sdcard/Download/network-monitor/domains/resolved_domains.csv | tail -20
```

### 2. Identify Tracking Domains
```bash
# Export DNS resolutions
adb shell cat /sdcard/Download/network-monitor/domains/resolved_domains.csv | grep -v "private\|localhost" > tracking_domains.csv

# Analyze in Excel or Google Sheets
```

### 3. Debug Network Connectivity
```bash
# Check active connections in real-time
adb shell tail -f /sdcard/Download/network-monitor/logs/activity/tcp_connections.txt

# Monitor connection state changes
adb shell tail -f /sdcard/Download/network-monitor/logs/activity/connection_state.csv
```

### 4. Automate Reports
```bash
#!/bin/bash
# Run daily and generate report
adb shell /sdcard/Download/network_monitor.sh &
sleep 3600  # Run for 1 hour

# Pull logs
adb pull /sdcard/Download/network-monitor/ ./reports_$(date +%Y-%m-%d)/

# Parse JSON
cat ./reports_*/stats/*.json | jq '.unique_domains' | sort -u
```

---

## Performance Metrics

| Metric | Value | Notes |
|--------|-------|-------|
| Memory Usage | ~5-10 MB | Grows slightly with DNS cache |
| CPU Usage | 1-5% | Per 2-second cycle |
| Disk I/O | ~50-100 KB per cycle | Temporary files in `.cache` |
| DNS Lookup Time | 100-2000ms | Depends on fallback method |
| Log Retention | Daily | Old activity logs auto-deleted |

---

## Security Considerations

⚠️ **Important Notes:**

1. **Root Access:** Full network monitoring requires root. Non-root users see only their own connections.
2. **Data Privacy:** DNS queries and domain resolutions are sent to `ip-api.com` (public API). Consider privacy implications.
3. **Storage:** Logs contain network metadata (IPs, domains, UIDs). Store securely.
4. **ADB Access:** ADB shell gives device-wide access. Enable only when needed.

---

## Support & Troubleshooting

### Check Script Version
```bash
adb shell head -5 /sdcard/Download/network_monitor.sh
```

### Generate Debug Report
```bash
# System info
adb shell uname -a
adb shell getprop ro.build.version.release

# Termux info
adb shell which bash
adb shell command -v dig curl jq

# Available space
adb shell df /sdcard/Download/

# Recent logs
adb shell tail -20 /sdcard/Download/network-monitor/logs/monitor.log
```

### Report Issues
If you encounter problems:
1. Collect debug report (above)
2. Check troubleshooting section
3. Open GitHub issue with logs and device info

---

## License

This script is provided as-is for network monitoring on Android devices.

**Version:** 2.1  
**Last Updated:** 2026-09-02  
**Maintainer:** yassinhammami40-beep

# Android Network Monitor v3.0

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell Script](https://img.shields.io/badge/Shell_Script-121011?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Android](https://img.shields.io/badge/Android-3DDC84?logo=android&logoColor=white)](https://www.android.com/)
[![Termux](https://img.shields.io/badge/Termux-black?logo=android&logoColor=white)](https://termux.com/)
![Status](https://img.shields.io/badge/Status-Active%20Development-green)

> **No-root Android network monitor** that tells you which app on your phone talked to which domain — built as two cooperating scripts to work around a real Android OS restriction (see below).

## Why two scripts?

On Android 10+, `/proc/net/tcp` and `/proc/net/udp` — the files that list active
network connections — are only readable by `adb shell` (the `shell` user), not
by regular apps like Termux. But Termux is where working DNS tools (`dig`,
`curl`) actually live. Neither environment can do the whole job alone, and
neither trick (reaching into Termux's sandbox from `adb shell`, or granting
Termux `/proc` access) works without root.

The fix: split the work across both environments, and let them hand off data
through shared storage (`/sdcard`) instead of talking to each other directly.

```
┌─────────────────────┐         ┌──────────────────────┐
│   collector.sh       │  writes │      .queue/          │  reads  │   resolver.sh        │
│   (via adb shell)    │ ──────▶ │   raw_ips.txt          │ ──────▶ │   (inside Termux)    │
│   has /proc access   │         │   (shared file)        │         │   has dig/curl        │
└─────────────────────┘         └──────────────────────┘         └──────────────────────┘
        │                                                                    │
        ▼                                                                    ▼
  ip_history_*.csv                                              resolved_domains.csv
  (IP, port, UID,                                                (IP → domain/org,
   package name)                                                  deduped)
        │                                                                    │
        └───────────────────────────┬────────────────────────────────────────┘
                                     ▼
                    package_domain_report_*.csv
                    (which app talked to which domain)
```

## Quick Start

### 1. Collector — run via `adb shell` (needs `/proc` access)

```bash
git clone https://github.com/yassinhammami40-beep/android-network-monitor.git
cd android-network-monitor
adb push collector.sh /data/local/tmp/
adb shell sh /data/local/tmp/collector.sh &
```

### 2. Resolver — run inside the Termux app (needs `dig`/`curl`)

```bash
# from your computer
adb push resolver.sh /sdcard/Download/

# then inside the Termux app itself:
pkg install dnsutils curl jq   # if not already installed
chmod +x /sdcard/Download/resolver.sh
bash /sdcard/Download/resolver.sh &
```

Both need to be running at the same time — the collector alone gives you raw
IPs and package names but no domain names; the resolver alone has nothing to
resolve without the collector feeding it data.

## What you get

All output lives under `/sdcard/Download/network-monitor/`:

| File | What it is | Update pattern |
|---|---|---|
| `logs/activity/tcp_connections.txt` | Human-readable snapshot of current TCP connections | Overwritten every cycle |
| `logs/activity/udp_connections.txt` | Same, for UDP | Overwritten every cycle |
| `ip_history_YYYY-MM-DD.csv` | Every connection seen today: IP, port, protocol, UID, **package name** | Append-only |
| `domains/resolved_domains.csv` | IP → domain/org, resolved once per IP | Append-only, deduped |
| `domains/package_domain_report_YYYY-MM-DD.csv` | **The main answer**: which package talked to which domain | Fully rewritten every ~60s |

Check the actual answer to "what is my phone doing" with:
```bash
cat /sdcard/Download/network-monitor/domains/package_domain_report_$(date +%Y-%m-%d).csv
```

Since that file is rewritten (not appended) each cycle, use `watch` rather
than `tail -f` to view it live without garbled output:
```bash
watch -n 5 cat /sdcard/Download/network-monitor/domains/package_domain_report_$(date +%Y-%m-%d).csv
```

## Domain resolution fallback chain

For each IP, the resolver tries, in order:
1. **Reverse DNS** (`dig -x`) — exact hostname if a PTR record exists
2. **Reverse-DNS API** (`curl` + `jq` against a public API) — fallback if `dig` finds nothing
3. **ASN/org lookup** (`ipinfo.io`) — the owning organization (e.g. "Cloudflare,
   Inc.") even when no hostname exists at all, which is common for CDN/cloud IPs

Results are tagged with a confidence level: `high` (exact hostname), `medium`
(org name only), `low` (nothing found).

## Known limitations

- **Polling, not packet capture.** This reads connection state every 5 seconds
  — very short-lived connections between polls won't be seen. For full packet
  inspection, a VPN-based tool (e.g. PCAPdroid, NetGuard) is more appropriate.
- **No root required, but two processes across two contexts.** You need `adb`
  tethered to your computer for the collector; this isn't an on-device-only,
  leave-it-running-for-days setup.
- **UID → package resolution** uses `pm list packages -U` (no root needed).
  System UIDs below 10000 often aren't listed and will show as `uid_<N>`.

## License

MIT

# Android Network Monitor

A beginner-friendly Android shell script for monitoring network activity via Android's /proc filesystem.

This project explores how Android network sockets map to processes, UIDs, and application package names.

## Features

- Network interfaces and traffic counters
- TCP connections (IPv4)
- TCP6 connections (IPv6)
- UDP sockets (IPv4)
- UDP6 sockets (IPv6)
- Local and remote IP addresses
- Ports
- Socket states
- UIDs and PIDs
- Android package names
- Socket inodes

## How it works

The script reads /proc/* network tables, extracts socket inodes, and resolves which process owns each socket by scanning process file descriptors. From the PID it derives the UID and then the Android package name (when available). The mapping flow is shown below:

```
/proc/net/tcp
/proc/net/tcp6
/proc/net/udp
/proc/net/udp6
    |
    v
 Socket inode
    |
    v
 /proc/<PID>/fd/   (find socket:<inode>)
    |
    v
   PID
    |
    v
   UID
    |
    v
Android package
```

## Requirements

- An Android device
- ADB shell access
- Common Android shell utilities (grep, awk, readlink, etc.)
- Permission to read the necessary /proc entries

The script is designed for learning and experimentation and does not require root for its basic operations, though some information may be restricted on newer Android versions.

## Running

Copy the script to the device:

```bash
adb push network.sh /data/local/tmp/
```

Make it executable:

```bash
adb shell chmod +x /data/local/tmp/network.sh
```

Run it (background):

```bash
adb shell /data/local/tmp/network.sh &
```

You can also run it inside Termux if you have access to the same utilities and permissions.

Depending on Android version and permissions, some sockets or processes may be hidden.

## Example output

```
TIME      REMOTE IP         PORT  UID    PID    PACKAGE
03:19:42  142.251.110.119   443   10220  20247  com.google.android.youtube
03:19:42  172.217.116.4     443   10220  20247  com.google.android.youtube
03:20:24  41.231.245.114    443   1000   -      com.miui.daemon
03:23:26  41.231.245.33     443   10231  22747  com.miui.videoplayer
```

## Current limitations

- IPv4 parsing/reporting is more complete than IPv6 parsing.
- Some sockets cannot be associated with a PID because of Android permissions and process visibility.
- Some system sockets may appear without an associated process.
- The script reports IP addresses directly and does not perform reverse DNS lookups reliably.
- Output formatting and filtering can be improved.

## Why I built this

This started as a learning project to understand how Android and Linux represent network connections internally. The goal is to learn by building rather than only using existing network-monitoring tools.

## Future improvements

- Improve IPv6 parsing
- Improve PID/socket resolution (handle restricted processes)
- Better output formatting and filtering options
- Connection history and per-app traffic statistics
- More robust Android compatibility (support for different shell environments)

## Status

Early-stage learning project. The project is actively being improved as I learn more about Android, Linux, networking, shell scripting, and system internals.

Android Network Monitor

A beginner-friendly Android shell script for monitoring network activity through Android's "/proc" filesystem.

The project explores how Android network sockets can be connected to processes, UIDs, and application package names.

What it monitors

- Network interfaces and traffic counters
- TCP connections
- TCP6 connections
- UDP sockets
- UDP6 sockets
- Local and remote IP addresses
- Ports
- Socket states
- UIDs
- PIDs
- Android package names
- Socket inodes

How it works

The main socket-to-application mapping works approximately like this:

/proc/net/tcp
/proc/net/tcp6
/proc/net/udp
/proc/net/udp6
        |
        v
   Socket inode
        |
        v
 /proc/<PID>/fd/
        |
        v
       PID
        |
        v
       UID
        |
        v
 Android package

The script uses the socket inode to search process file descriptors and identify which process owns a network socket. The process UID can then be associated with an Android package.

Requirements

- Android device
- ADB shell access
- Android shell utilities
- Permission to read the required "/proc" information

The script is designed for learning and experimentation and does not require root for its basic operation.

Running

Copy the script to the Android device:

adb push network.sh /data/local/tmp/

Make it executable:

adb shell chmod +x /data/local/tmp/network.sh

Run it:

adb shell /data/local/tmp/network.sh &

Depending on the Android version and permissions, some sockets or processes may not be visible.

Example

Example output:

TIME      REMOTE IP         PORT  UID    PID    PACKAGE
03:19:42  142.251.110.119   443   10220  20247  com.google.android.youtube
03:19:42  172.217.116.4     443   10220  20247  com.google.android.youtube
03:20:24  41.231.245.114    443   1000   -      com.miui.daemon
03:23:26  41.231.245.33     443   10231  22747  com.miui.videoplayer

Current limitations

- IPv4 reporting is currently more complete than IPv6 parsing.
- Some sockets cannot be associated with a PID because of Android permissions and process visibility.
- Some system sockets may appear without an associated process.
- IP addresses are reported directly; the script does not currently perform reliable reverse-DNS resolution.
- Output formatting and filtering can still be improved.

Why I built this

This started as a learning project to understand how Android and Linux represent network connections internally.

The goal is to learn by building rather than simply using existing network-monitoring tools.

Future improvements

- Improve IPv6 parsing
- Improve PID/socket resolution
- Better output formatting
- Connection history
- Traffic statistics per application
- Better filtering
- More robust Android compatibility

Status

Early-stage learning project.

The project is actively being improved as I learn more about Android, Linux, networking, shell scripting, and system internals.

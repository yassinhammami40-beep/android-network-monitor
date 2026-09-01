# Contributing to Android Network Monitor

Thank you for your interest in contributing! This document provides guidelines and instructions for contributing to the Android Network Monitor project.

## 🤝 Ways to Contribute

- **Report Bugs** — Found a crash or unexpected behavior?
- **Suggest Features** — Ideas for improvements or new features?
- **Improve Documentation** — Help make README/docs clearer
- **Add Code** — Fix bugs or implement new features
- **Test** — Report compatibility issues on different Android versions

## 🐛 Reporting Issues

### Before Creating an Issue
- Check existing issues to avoid duplicates
- Test with the latest version
- Gather information about your device and setup

### Issue Template
When reporting a bug, include:
```
**Device Info:**
- Android version:
- Device model:
- Termux version (if using Termux):

**Issue:**
[Clear description of the problem]

**Steps to Reproduce:**
1. ...
2. ...
3. ...

**Expected Behavior:**
[What should happen]

**Actual Behavior:**
[What actually happens]

**Logs:**
[Include /sdcard/Download/network-monitor/logs/monitor.log]

**Screenshots:**
[If applicable]
```

## 💡 Feature Requests

Describe:
1. **What** — What feature or improvement?
2. **Why** — What problem does it solve?
3. **How** — How would it work?

Example:
```
Title: Add SQLite database output format

Description: Currently supports TXT/CSV/JSON. SQLite would enable 
efficient querying of historical data and reduce file bloat.

Use Case: Privacy auditing across multiple monitoring sessions.
```

## 🔧 Code Contributions

### Setup Development Environment

```bash
# Clone the repo
git clone https://github.com/yassinhammami40-beep/android-network-monitor.git
cd android-network-monitor

# Create a feature branch
git checkout -b feature/your-feature-name
```

### Code Style Guidelines

**Shell Script Standards:**
- Use meaningful variable names (not `$a`, `$b`)
- Add comments for complex logic
- Keep lines under 100 characters when possible
- Use `set -e` for error handling
- Quote variables: `"$var"` not `$var`

Example:
```bash
# Good
resolve_package_name() {
  local uid=$1
  # Use package manager to resolve UID to package name
  pm list packages --uid "$uid" | cut -d: -f2
}

# Avoid
rp() {
  pm list packages --uid $1 | cut -d: -f2
}
```

### Testing Checklist

Before submitting, test:
- ✅ Runs without errors on Termux
- ✅ Handles IPv4 and IPv6 connections
- ✅ DNS resolution works (or gracefully falls back)
- ✅ Output files are created correctly
- ✅ Connection state tracking works
- ✅ No breaking changes to output formats

### Commit Messages

Write clear, descriptive commit messages:

```
✨ Add SQLite database output support

- Implements new SQLite output format
- Maintains backward compatibility with TXT/CSV/JSON
- Adds database schema with indexes for efficient queries
- Includes migration helper for existing logs

Fixes #42
```

**Commit Prefixes:**
- ✨ `feat:` — New feature
- 🐛 `fix:` — Bug fix
- 📝 `docs:` — Documentation
- 🎨 `style:` — Code style
- ♻️ `refactor:` — Code refactoring
- ⚡ `perf:` — Performance improvement
- ✅ `test:` — Tests
- 🔧 `chore:` — Build/tooling

## 📝 Pull Request Process

1. **Fork & Branch**
   ```bash
   git checkout -b feature/your-feature
   ```

2. **Make Changes**
   - Keep commits focused and logical
   - Test thoroughly
   - Update README if behavior changes

3. **Push & Create PR**
   ```bash
   git push origin feature/your-feature
   ```

4. **PR Description** — Include:
   - What does this PR do?
   - Why is it needed?
   - How to test?
   - Relevant issues/discussions

5. **Respond to Review**
   - Be open to feedback
   - Discuss trade-offs
   - Request re-review after changes

## 🧪 Testing

### Manual Testing on Termux

```bash
# Install required tools
pkg install netcat-openbsd net-tools

# Run the monitor
./network_monitor.sh

# Check output in real-time
tail -f /sdcard/Download/network-monitor/logs/activity/current.txt

# Verify DNS resolution
cat /sdcard/Download/network-monitor/domains/domain_history_*.csv | head -20

# Check for errors
cat /sdcard/Download/network-monitor/logs/monitor.log
```

### Test Scenarios

- [ ] Monitor with WiFi only
- [ ] Monitor with mobile data only
- [ ] Monitor with both WiFi and mobile
- [ ] Test after device sleep/wake
- [ ] Test IPv6 addresses (if available)
- [ ] Test with high network activity
- [ ] Test DNS resolution with no internet
- [ ] Test on multiple Android versions

## 📚 Documentation

### README Updates
- Keep it current with code changes
- Add examples for new features
- Include troubleshooting for common issues
- Update architecture diagrams if needed

### Code Comments
- Explain the "why" not the "what"
- Document complex algorithms
- Note edge cases and limitations

Example:
```bash
# Bad: Obvious what the code does
inode=$(echo "$entry" | awk '{print $10}')

# Good: Explains why we extract this
# Extract socket inode (field 10) to match with /proc/fd/ entries
inode=$(echo "$entry" | awk '{print $10}')
```

## 🔐 Security Considerations

When contributing:
- Don't log sensitive data (credentials, tokens)
- Validate external API responses (ip-api.com)
- Consider rate limiting when adding external API calls
- Document privacy implications

## 📋 Development Roadmap

Priority improvements:
1. **Error Resilience** — Better handling of edge cases
2. **Performance** — Optimize parsing for high-traffic devices
3. **Local DNS** — Replace ip-api.com with local resolution
4. **SQLite Export** — Add database output format
5. **Android 14+** — Test and fix for latest Android versions

## ❓ Questions?

- **Issues/Discussions** — Use GitHub Issues for bugs, Discussions for questions
- **Email** — yassinhammami40@gmail.com

## 📜 License

By contributing, you agree your changes will be licensed under the MIT License.

---

**Thank you for contributing! 🙌**

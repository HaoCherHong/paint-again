# Security Policy

## Reporting a vulnerability

Please **do not** open a public issue for security problems. Instead, use
GitHub's [private vulnerability reporting](https://github.com/HaoCherHong/paint-again/security/advisories/new)
or email **rax333j@gmail.com** with:

- what the problem is and what an attacker could do with it,
- the steps or a sample file that reproduces it,
- the app version and macOS version.

You will get a reply within a week. Once a fix ships, you are credited in the
release notes unless you prefer not to be.

## Scope

Paint Again is an offline, sandboxed app with no network access, so the most
likely issues are in reading untrusted image files (crashes or memory
corruption on a crafted PNG / JPEG / BMP / GIF / TIFF / HEIC) and in anything
that escapes the App Sandbox. Only the latest release (App Store or GitHub
Releases) is supported.

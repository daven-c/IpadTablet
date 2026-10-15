# Security Policy

## Scope

The Mac daemon moves your cursor in response to data received on a local TCP
port (`127.0.0.1:12345`, tunnelled to the iPad over USB by `iproxy`). It binds
no external interface. Reports about anything that lets another process,
device or network peer inject input, or that makes the daemon or app execute
unintended code, are in scope.

## Reporting a vulnerability

Please **don't open a public issue**. Use GitHub's private reporting:
**Security → Report a vulnerability** on this repository. Include steps to
reproduce and the macOS / iOS versions involved. You can expect an initial
response within a week.

## Supported versions

Only the latest commit on `main` is supported.

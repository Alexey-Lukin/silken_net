# Security Policy

## Reporting a vulnerability

Please **do not** open a public issue for a security vulnerability.

Report it privately through
[GitHub Security Advisories](https://github.com/Alexey-Lukin/silken_net/security/advisories/new)
(repo → **Security** → **Advisories** → *Report a vulnerability*). We aim to
acknowledge within **72 hours** and to ship a fix or mitigation for high-severity
issues within **14 days**.

## Credit

When a reported vulnerability is fixed, we credit the reporter(s) in the security
advisory and/or the release notes, unless the reporter asks to remain anonymous.

## Scope

In scope: the Rails backend (`app/`, `lib/`), the smart contracts (`contracts/`),
the firmware (`firmware/`), and the CI/CD + deploy configuration (`.github/`,
`deploy/`, `terraform/`).

## Known, documented limitations (not undisclosed vulnerabilities)

Some hardware-gated weaknesses are tracked **openly** in the canon and are not
treated as secret 0-days — for example the transitional **AES-128-ECB** LoRa link
(no MAC/IV; replay/bit-flip exposure), which is documented in `docs/03_05` and is
bench-gated for migration to AES-128-CCM. The open security backlog lives in
`docs/00_07` (the `SEC.*` items).

## Safe harbor

Good-faith security research — testing against your own deployment, not accessing
or exfiltrating other users' data, and not degrading the service — will not be
pursued. Thank you for helping keep SilkenNet and the forests it watches safe.

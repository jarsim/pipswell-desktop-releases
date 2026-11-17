# Security policy

Pipswell Desktop places real orders on MetaTrader 5 accounts once its safety switches are turned off, so
security reports are taken seriously and answered quickly.

## Reporting a vulnerability

E-mail **support@pipswell.trade** with the subject "Security". Please include what you found, the version
(`pipswell --version`, or the version in the app's status bar), your operating system, and steps to reproduce. Do not include
account passwords, licence files or other secrets.

- You get an acknowledgement within 3 working days.
- We confirm or rule out the issue and tell you the planned fix date; a fix for a serious issue ships as a
  signed release that `pipswell update` and the in-app update offer.
- Please give us reasonable time to fix it before you publish. We credit reporters who want it.

Do not test against other people's accounts or against pipswell.trade's production services; use your own
installation and demo accounts.

## Supported versions

Only the newest release on each channel (stable and beta) gets security fixes. Update with `pipswell update`
or the Update button in the app.

## How releases are protected

- From 0.2.0.dev29 on, every release list is signed with an offline Ed25519 key and the installers and the
  updater refuse anything unsigned or tampered with; every download is checked against its SHA-256. (The update
  INTO 0.2.0.dev29 still runs the previous version's updater, which checks the SHA-256 only.)
- From 0.2.0.dev29 on, `pipswell update` and the in-app Update button refuse to update while any account has an
  open position or pending order. Re-running the install command does not check this, and the variable
  `PIPSWELL_UPDATE_WITH_POSITIONS=1` overrides it on purpose.
- The licence is a short-lived, server-signed entitlement (at most 24 hours, refreshed hourly). From 0.2.0.dev30
  on, every release build enforces it: a feature needs both the signed licence and the plan. A lapsed licence only
  stops something new from opening; closing, SL/TP changes and the guards on positions already open never ask
  for one.
- Every release publishes a software bill of materials (`sbom.cdx.json`, CycloneDX) next to its files.

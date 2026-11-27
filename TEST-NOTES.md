# Tester notes

There is no test build at the moment. Testers use the release **v10** (2026-11-27,
[RELEASE-NOTES.md](RELEASE-NOTES.md)). Downloads: [DOWNLOADS.md](DOWNLOADS.md).

## Updates

- On v10: Pipa Helper > System > Updates > Check for updates, then Install update. The update goes into the second
  system slot (about 100 MB, a delta). The tablet restarts one time at the end. Your apps and data stay.
- On v9.3 or older: flash v10 one time with the PC flash script and answer `1` (keep data). After that, Pipa Helper
  installs the updates.
- On an older test build: Check for updates. If Pipa Helper shows no update, flash v10 with the PC flash script
  (answer `1`).
- Do not install an update below 30 % battery without the charger.
- Pipa Helper updates show only releases. When there is a new test build, the maintainer gives it to the testers by
  hand (a package for the PC flash script).

## Report a problem

- Right after the problem, without a restart: Pipa Helper > System > Collect logs. Send the file. It has no personal
  data.
- After a spontaneous restart: do Collect logs after the restart. The file also has the log of the previous boot.
- Open a report on GitHub: https://github.com/Stefan-Atanasov/pipa-cos17-port/issues/new/choose. Write the build
  (Pipa Helper > System > Updates shows it), clean install or update, the steps, what you expected and what
  happened. Attach the log file.
- Before you report a battery, heat or speed problem, remove "tweak" and performance modules
  ([KNOWN-ISSUES.md](KNOWN-ISSUES.md)).
- Questions: support group https://t.me/cosforpipa.

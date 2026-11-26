# pt172 test build: tester notes

Test build of the ColorOS 17 port for the Xiaomi Pad 6 (`pipa`), for testers only. Base: pt167 (v10 release
candidate) + the fixes below. Kernel: walt-hi16 with KernelSU (SukiSU Nova, built in). The current release is
v9.3 ([RELEASE-NOTES.md](RELEASE-NOTES.md)).

## Install

- From pt167: Pipa Helper > System > Updates > Check for updates, then Install update (about 100 MB, a
  delta). The tablet restarts one time at the end. Your data stays.
- From v9.3 or older, or from another test build: there is no package for this build. Wait for v10.
- Do not install below 30 % battery without the charger.

## New since pt167

- Settings > System & update > Google settings: the Google Mobile Services switch is back. Off turns off Google
  Play services (and with it Quick Share); On turns them on again.
- Floating windows: up to 4 at the same time (before: 2; the third one closed the oldest).
- Back gesture: with Screen resolution = Low, the swipe from the right edge works again (left edge worked before).
- BGMI uses the same screen refresh rule as PUBG MOBILE.
- Charging limit (Settings > Battery): the limit also holds while the screen is off. Before, the tablet could charge
  past the limit while it slept.
- Smart Sidebar: with Screen resolution = Low, the sidebar has its normal size again (before: about 2 times too
  big).
- Collect logs (Pipa Helper > System): errors of the last hours are kept in a file that stays after a restart, and
  the app log reaches about 25 minutes back (before: about 13 minutes). The file stays below 10 MB.

## How bypass charging works (stock ColorOS)

- In a game, bypass charging starts only when Game Assistant > Bypass charging has "auto open" on, or when you turn
  it on in the Game Assistant panel. It starts at or above the level that you set there.
- It turns off when you disconnect the charger and while the screen is off. This is the same on stock ColorOS.

## Report a problem

- Report a problem: Pipa Helper > System > Collect logs right after the problem, without a restart, and send the
  file.

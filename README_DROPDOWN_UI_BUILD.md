# Exact Chinese Chess v35-plus dropdown UI source package

This source package changes the Kindle app UI so Mode and Level are real GTK dropdowns instead of cycle buttons.

Changed UI:
- Mode dropdown: Red / Black / 2P / Demo
- Level dropdown: Easy / Medium / Hard

Kept from v35-plus-easy-depth-config-watchdog:
- Book ON / BookOff button inside the app UI
- Pikafish wrapper v35-plus
- `pikafish_config.txt`
- Easy = configurable depth, default `EASY_DEPTH=3`
- Medium/Hard = configurable movetime
- BOOK.DAT diverse v5 support
- watchdog/log/config features

Important Kindle warning:
The original source comment said GTK ComboBox dropdowns may snap shut on the Kindle e-ink window manager. This package intentionally enables dropdowns because the user requested it. If it crashes or dropdown closes instantly, revert to the cycle-button UI or use a custom popup/menu fallback.

Build method:
Use the included GitHub Actions workflow `build-pw3.yml` or build in the provided ARMv7 Jessie Docker environment. This sandbox cannot compile the ARM GTK binary because it has no ARM Docker/cross-compiler/GTK headers.

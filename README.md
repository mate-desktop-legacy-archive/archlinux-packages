# Installing MATE on Arch Linux

The following will assist you:

  * <http://wiki.mate-desktop.org/archlinux_custom_repo>
  * <https://wiki.archlinux.org/index.php/MATE>

# Introduction

**NOTE! These PKGBUILDs are no longer maintained here.**

MATE is available from the official Arch Linux `[community]` repository, as
such stable MATE packages are now maintained by the Arch Linux Trusted Users.
This repository is only used for testing/developing the current in development
releases of MATE.

# Developing MATE packages for Arch Linux

The packages are now maintained by the Arch Linux Trusted Users.

## Submitting bugs

Please submit Arch Linux packaging bugs for MATE desktop to the Arch Linux bug
tracker.

  * <https://bugs.archlinux.org/>

If you find a bug in one of the MATE applications, applets or plugins then
please file it in the relevant MATE desktop repository issue tracker.

  * <https://github.com/mate-desktop/>

# Migrating to MATE 1.8

These notes describe the package removals and changes that will be required
by the Arch Linux packager when the tranisition to MATE 1.8 happens.

  * Remove `mate-document-viewer` and replace with `atril`.
  * Remove `mate-file-manager` and replace with `caja`.
  * Remove <insert all caja extensions here> and replace with `caja-extensions`.
  * Remove `mate-file-archiver` and replace with `engrampa`.
  * Remove `mate-image-viewer` and replace with `eom`.
  * Remove `mate-window-manager` and replace with `marco`.
  * Remove `mate-menu-editor` and replace with `mozo`.
  * Remove `mate-test-editor` and replace with `pluma`.
  * Remove `mate-character-map` as MATE 1.8 uses `gucharmap`.
  * Remove `mate-keyring` as MATE 1.8 uses `gnome-keyring`.
  * Remove `libmatekeyring` as MATE 1.8 uses `libsecret`.

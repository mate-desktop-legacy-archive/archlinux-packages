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
by the Arch Linux packager during tranisition to MATE 1.8 happens.

  * Replace `mate-document-viewer` with `atril`.
  * Replace `mate-file-manager` with `caja`.
  * Replace the following with `caja-extensions`.
    * `mate-file-manager-gksu`
    * `mate-file-manager-image-converter`
    * `mate-file-manager-open-terminal`
    * `mate-file-manager-sendto`
    * `mate-file-manager-share`
  * Replace `mate-file-archiver` with `engrampa`.
  * Replace `mate-image-viewer` with `eom`.
  * Replace `mate-window-manager` with `marco`.
  * Replace `mate-menu-editor` with `mozo`.
  * Replace `mate-test-editor` with `pluma`.
  * Remove `mate-character-map` as MATE 1.8 uses `gucharmap`.
  * Remove `mate-keyring` as MATE 1.8 uses `gnome-keyring`.
  * Remove `libmatekeyring` as MATE 1.8 uses `libsecret`.
  * Remove `mate-doc-utils` as MATE 1.8 uses `yelp-tools`.
  * Remove `libmatewnck` as MATE 1.8 uses `libwnck`.  

For more details:

  * <http://wiki.mate-desktop.org/status:1.8>

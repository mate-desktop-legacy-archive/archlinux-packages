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

## GTK2 and GTK3

The following packages can be build against GTK2 or GTK3.

  * atril
  * caja
  * caja-extensions
  * engrampa
  * eom
  * galculator
  * libmatekbd
  * libmateweather
  * marco
  * mate-control-center
  * mate-desktop
  * mate-media
  * mate-netbook
  * mate-netspeed
  * mate-notification-daemon
  * mate-panel
  * mate-polkit
  * mate-sensors-applet
  * mate-session-manager
  * mate-settings-daemon
  * mate-themes
  * mate-utils
  * pluma

These are the replacements you need to look out for:

    replaces.append(["gtk2", "gtk3"])
    replaces.append(["--with-gtk=2.0", "--with-gtk=3.0"])
    replaces.append(["libunique", "libunique3"])
    replaces.append(["vte", "vte3"])
    replaces.append(["libwnck", "libwnck3"])
    replaces.append(["gtkmm", "gtkmm3"])
    replaces.append(["gtksourceview2", "gtksourceview3"])


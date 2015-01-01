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

  * mate-desktop                [ DONE ]
  * libmatekbd                  [ DONE ]
  * libmateweather              [ DONE ]
  * caja                        [ DONE ]
  * caja-gtk3                   [ DONE ]
  * mate-polkit                 [ DONE ]
  * marco                       [ DONE ]
  * marco-gtk3                  [ DONE ]
  * mate-settings-daemon        [ DONE ]
  * mate-settings-daemon-gtk3   [ DONE ]
  * mate-session-manager        [ DONE ]
  * mate-session-manager-gtk3   [ DONE ]
  * mate-panel                  [ DONE ]
  * mate-panel-gtk3             [ DONE ]
  * mate-media                  [ DONE ]
  * mate-media-gtk3             [ DONE ]
  * mate-notification-daemon    [ DONE ]
  * mate-control-center         [ DONE ]
  * mate-control-center-gtk3    [ DONE ]
  * mate-screensaver            [ DONE ]
  * mate-screensaver-gtk3       [ DONE ]
  * engrampa                    [ DONE ]
  * engrampa-gtk3               [ DONE ]
  * mate-power-manager          [ DONE ]
  * mate-power-manager-gtk3     [ DONE ]
  * mate-system-monitor         [ DONE ]
  * atril                       [ DONE ]
  * atril-gtk3                  [ DONE ]
  * caja-extensions             [ DONE ]
  * caja-extensions-gtk3        [ DONE ]
  * mate-applets                [ DONE ]
  * mate-applets-gtk3           [ DONE ]
  * eom                         [ DONE ]
  * eom-gtk3                    [ DONE ]
  * mate-icon-theme-faenza      [ DONE ]
  * mozo                        [ DONE ]
  * mate-netbook                [ DONE ]      
  * mate-netbook-gtk3           [ DONE ]
  * mate-netspeed               [ DONE ]
  * mate-netspeed-gtk3          [ DONE ]
  * mate-sensors-applet         [ DONE ]
  * mate-sensors-applet-gtk3    [ DONE ]
  * mate-terminal               [ DONE ]
  * mate-terminal-gtk3          [ DONE ]
  * pluma                       [ DONE ]
  * pluma-gtk3                  [ DONE ]
  * mate-user-share             [ DONE ]
  * mate-user-share-gtk3        [ DONE ]
  * mate-utils                  [ DONE ]
  * mate-utils-gtk3             [ DONE ]
  * python2-caja                [ DONE ]
  * python2-caja-gtk3           [ DONE ]
  * galculator                  [ DONE ]
  * mate-user-guide
  *"https://aur.archlinux.org/packages/ob/obex-data-server/obex-data-server.tar.gz"
  * blueman

These are the replacements you need to look out for:

    replaces.append(["gtk2", "gtk3"])
    replaces.append(["--with-gtk=2.0", "--with-gtk=3.0"])
    replaces.append(["libunique", "libunique3"])
    replaces.append(["vte290", "vte"])
    replaces.append(["libwnck", "libwnck3"])
    replaces.append(["gtkmm", "gtkmm3"])
    replaces.append(["gtksourceview2", "gtksourceview3"])
    replaces.append(["webkitgtk2", "webkitgtk"])

# TODO

  * Add GTK2/3 versions in the description of caja-extensions packages. [ DONE ]
  * Remove obsolete `pkgdesc+=` references.                             [ DONE ]
  * Disable python for the GTK3 builds of Pluma and eom.                [ DONE ]
  * Remove Python from libmateweather.                                  [ DONE ]
  * Mark GTK2-versions as STABLE and GTK3-versions as EXPERIMENTAL.     [ DONE ]
  * Disable mpaste and mate-conf in mate-desktop                        [ DONE ]
  * Clean up redundant deps on yelp-tools                               [ DONE ]
  * Currently `gnome-main-menu` and `mozo` are GTK2 only.
  * Collect all build logs and PKGBUILDs
  * eom requires python2-gobject2.

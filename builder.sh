#!/usr/bin/env bash

TEST_DEVTOOLS=$(pacman -Qq devtools 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "ERROR! You must install 'devtools'."
    exit 1
fi

TEST_DEVTOOLS=$(pacman -Qq darkhttpd 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "ERROR! You must install 'darkhttpd'."
    exit 1
fi

if [ $(id -u) != "0" ]; then
    echo "ERROR! You must be 'root'."
    exit 1
fi

# http://wiki.mate-desktop.org/status:1.8
BUILD_ORDER=(
    mate-common
    mate-desktop
    libmatekbd
    libmateweather
    mate-icon-theme
    mate-dialogs
    caja
    mate-polkit
    marco
    mate-settings-daemon
    mate-session-manager
    mate-menus
    mate-panel
    mate-media
    mate-backgrounds
    mate-themes
    mate-notification-daemon
    mate-control-center
    mate-screensaver
    engrampa
    mate-power-manager
    mate-system-monitor
    atril
    caja-extensions
    mate-applets
    #mate-bluetooth                     # Not yet supported
    mate-calc
    eom
    mate-icon-theme-faenza
    #mate-indicator-applet              # For the AUR
    mozo
    mate-netbook
    mate-netspeed
    mate-sensors-applet
    mate-system-tools
    mate-terminal
    pluma
    mate-user-share
    mate-utils
    python2-caja
)

BASEDIR=$(dirname $(readlink -f ${0}))
MATE_VER=1.7

# Show usage information.
function usage() {
    echo "$(basename ${0}) - MATE build tool for Arch Linux"
    echo
    echo "Usage: $(basename ${0}) -t [task]"
    echo
    echo "Options:"
    echo "-h  Shows this help message."
    echo "-t  Provide a task to run which can be one of:"
    echo "      build       Build MATE packages."
    echo "      check       Check upstream for new source tarballs."
    echo "      repo        Create a package repository in '${HOME}/mate/'"
    echo "      sync        'rsync' a repo to ${RSYNC_UPSTREAM}."
    echo
    echo "Each of the tasks above run automatically and operate over the entire"
    echo "package tree."
}

function config_builder() {
    ln -s /usr/bin/archbuild /usr/local/bin/mate-unstable-i686-build 2>/dev/null
    ln -s /usr/bin/archbuild /usr/local/bin/mate-unstable-x86_64-build 2>/dev/null
    rm /usr/local/bin/mate-unstablepkg 2>/dev/null

    # Augment /usr/share/devtools/pacman-gnome-unstable.conf
    cp /usr/share/devtools/pacman-gnome-unstable.conf /usr/share/devtools/pacman-mate-unstable.conf
    sed -i s'/gnome/mate/' /usr/share/devtools/pacman-mate-unstable.conf
    sed -i '0,/Include = \/etc\/pacman\.d\/mirrorlist/s///' /usr/share/devtools/pacman-mate-unstable.conf
    echo "SigLevel = Optional TrustAll"   >  /tmp/mate-unstable.conf
    echo "Server = http://localhost:8088" >> /tmp/mate-unstable.conf
    sed -i '/\[mate-unstable\]/r /tmp/mate-unstable.conf' /usr/share/devtools/pacman-mate-unstable.conf    
}

function repo_update() {
    if [ ! -d /var/local/mate-unstable ]; then
        mkdir -p /var/local/mate-unstable
    fi
    repo-add --new /var/local/mate-unstable/mate-unstable.db.tar.gz /var/local/mate-unstable/*.pkg.tar.xz
}

function httpd_stop() {
    if [ -f /tmp/mate-unstable-darkhttpd.pid ]; then
        local DARK_PID=`cat /tmp/mate-unstable-darkhttpd.pid`
        kill -9 ${DARK_PID}
        rm /tmp/mate-unstable-darkhttpd.pid
    else
        killall darkhttpd
    fi
}

function httpd_start() {
    if [ -f /tmp/mate-unstable-darkhttpd.pid ]; then
        httpd_stop
    fi
    rm /tmp/mate-unstable-http.log 2>/dev/null
    darkhttpd /var/local/mate-unstable/ --port 8088 --daemon --log /tmp/mate-unstable-darkhttpd.log --pidfile /tmp/mate-unstable-darkhttpd.pid
}

# Build packages that are not at the current version.
function tree_build() {
    local PKG=${1}
    cd ${PKG}
    local INSTALLED=$(pacman -Q `basename ${PKG}` 2>/dev/null | cut -f2 -d' ')
    local PKGBUILD_VER=$(grep -E ^pkgver PKGBUILD | cut -f2 -d'=' | head -n1)
    local PKGBUILD_REL=$(grep -E ^pkgrel PKGBUILD | cut -f2 -d'=')
    local PKGBUILD=${PKGBUILD_VER}-${PKGBUILD_REL}

    for CHROOT_ARCH in i686 x86_64
    do
        echo " - Looking for *${PKGBUILD}*.pkg.tar.xz"
        if [ ! -f *${PKGBUILD}-${CHROOT_ARCH}.pkg.tar.xz ] && [ ! -f *${PKGBUILD}-any.pkg.tar.xz ]; then
            echo " - Building ${PKG}"
            mate-unstable-${CHROOT_ARCH}-build
            if [ $? -ne 0 ]; then
                echo " - Failed to build ${PKG} for ${CHROOT_ARCH}. Stopping here."
                kill -9 ${DARKHTTPD_PID}
                exit 1
            fi
            cp *.pkg.tar.xz /var/local/mate-unstable/
            repo_update
        else
            # Newer package in tree than in the repo. Copy it over.
            if [ ! -f /var/local/mate-unstable/*${PKGBUILD}*.pkg.tar.xz ]; then
                cp *.pkg.tar.xz /var/local/mate-unstable/
                repo_update
            fi
        fi
    done
}

# Check for new upstream releases.
function tree_check() {
    local PKG=${1}

    # Account for version differences.
    local CHECK_VER="${MATE_VER}"

    if [ "${PKG}" == "python2-caja" ]; then
        UPSTREAM_PKG="python-caja"
    else
        UPSTREAM_PKG="${PKG}"
    fi

    if [ ! -f /tmp/${CHECK_VER}_SUMS ]; then
        echo " - Downloading MATE ${CHECK_VER} SHA1SUMS"
        wget -c -q http://pub.mate-desktop.org/releases/${CHECK_VER}/SHA1SUMS -O /tmp/${CHECK_VER}_SUMS
    fi
    echo " - Checking ${UPSTREAM_PKG}"
    IS_UPSTREAM=$(grep -E ${UPSTREAM_PKG}-[0-9]. /tmp/${CHECK_VER}_SUMS)
    if [ -n "${IS_UPSTREAM}" ]; then
        local UPSTREAM_TARBALL=$(grep -E ${UPSTREAM_PKG}-[0-9]. /tmp/${CHECK_VER}_SUMS | cut -c43- | tail -n1)
        local UPSTREAM_SHA1=$(grep -E ${UPSTREAM_PKG}-[0-9]. /tmp/${CHECK_VER}_SUMS | cut -c1-40 | tail -n1)
        local DOWNSTREAM_VER=$(grep -E ^pkgver ${PKG}/PKGBUILD | cut -f2 -d'=')
        local DOWNSTREAM_TARBALL="${UPSTREAM_PKG}-${DOWNSTREAM_VER}.tar.xz"
        local DOWNSTREAM_SHA1=$(grep -E ^sha1 ${PKG}/PKGBUILD | cut -f2 -d"'")
        if [ "${UPSTREAM_TARBALL}" != "${DOWNSTREAM_TARBALL}" ]; then
            echo " +---> Upstream tarball differs : ${UPSTREAM_TARBALL}"
        fi
        if [ "${UPSTREAM_SHA1}" != "${DOWNSTREAM_SHA1}" ]; then
            echo " +---> Upstream SHA1SUM differs : ${UPSTREAM_SHA1}"
        fi
    else
        echo " +---> No upstream version of ${PKG} detected. Skipping."
    fi
}

# Create a package repository.
function tree_repo() {
    echo "Action : repo"

    source /etc/makepkg.conf

    echo " - Cleaning repository."
    rm -rf ${HOME}/${MATE_VER}/${CARCH} 2>/dev/null
    mkdir -p ${HOME}/${MATE_VER}/${CARCH}

    for PKG in ${BUILD_ORDER[@]};
    do
        # The following packages are not suitable for [community] so don't add them
        # to the repo.
        if [ "${PKG}" == "mate-bluetooth" ] || [ "${PKG}" == "mate-indicator-applet" ] ; then
            continue
        fi
        cd ${BASEDIR}/${PKG}
        local PKGBUILD_VER=$(grep -E ^pkgver PKGBUILD | cut -f2 -d'=')
        local PKGBUILD_REL=$(grep -E ^pkgrel PKGBUILD | cut -f2 -d'=')
        local PKGBUILD=${PKGBUILD_VER}-${PKGBUILD_REL}
        for FILE in $(ls -1 *${PKGBUILD}*.pkg.tar.xz 2>/dev/null)
        do
            cp -v ${FILE} ${HOME}/${MATE_VER}/${CARCH}/
        done
    done

    repo-add --new --files ${HOME}/${MATE_VER}/${CARCH}/mate.db.tar.gz ${HOME}/${MATE_VER}/${CARCH}/*.pkg.tar.xz
}

# `rsync` repo upstream.
function tree_sync() {
    echo "Action : sync"
    source /etc/makepkg.conf

    # Modify this accordingly.
    local RSYNC_UPSTREAM="mate@mate.flexion.org::mate-${MATE_VER}"

    if [ -L ${HOME}/${MATE_VER}/${CARCH}/mate.db ]; then
        rsync -av --delete --progress ${HOME}/${MATE_VER}/${CARCH}/ ${RSYNC_UPSTREAM}/${CARCH}/
    else
        echo "A valid 'pacman' repository was not detected. Run './${0} -t repo' first."
    fi
}

function tree_run() {
    local ACTION=${1}
    echo "Action : ${ACTION}"

    config_builder
    repo_update
    httpd_start
    
    for PKG in ${BUILD_ORDER[@]};
    do
        cd ${BASEDIR}
        tree_${ACTION} ${PKG}
    done
    
    httpd_stop
}

TASK=""
OPTSTRING=ht:
while getopts ${OPTSTRING} OPT; do
    case ${OPT} in
        h) usage; exit 0;;
        t) TASK=${OPTARG};;
        *) usage; exit 1;;
    esac
done
shift "$(( $OPTIND - 1 ))"

if [ "${TASK}" == "build" ] ||
   [ "${TASK}" == "check" ]; then
    tree_run ${TASK}
elif [ "${TASK}" == "repo" ] || [ "${TASK}" == "sync" ]; then
    tree_${TASK}
else
    usage
    exit 1
fi

# Clean up.
rm -f /tmp/*_SUMS 2>/dev/null

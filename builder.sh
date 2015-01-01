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

MACHINE=$(uname -m)

# http://wiki.mate-desktop.org/status:1.10
CORE=(
    mate-common
    mate-desktop
    mate-user-guide
    libmatekbd
    libmatemixer
    libmateweather
    mate-icon-theme
    caja
    caja-gtk3
    mate-polkit
    marco
    marco-gtk3
    mate-settings-daemon
    mate-settings-daemon-gtk3
    mate-session-manager
    mate-session-manager-gtk3
    mate-menus
    mate-panel
    mate-panel-gtk3
    mate-backgrounds
    mate-themes
    mate-notification-daemon
    mate-control-center
    mate-control-center-gtk3
    mate-screensaver
    mate-screensaver-gtk3
    mate-media
    mate-media-gtk3
    mate-power-manager
    mate-power-manager-gtk3
    mate-system-monitor
)

EXTRA=(
    atril
    atril-gtk3
    caja-extensions
    caja-extensions-gtk3
    engrampa
    engrampa-gtk3
    eom
    eom-gtk3
    mate-applets
    mate-applets-gtk3
    mate-icon-theme-faenza
    mate-netbook
    mate-netbook-gtk3
    mate-netspeed
    mate-netspeed-gtk3
    mate-sensors-applet
    mate-sensors-applet-gtk3
    mate-terminal
    mate-terminal-gtk3
    mate-user-share
    mate-user-share-gtk3
    mate-utils
    mate-utils-gtk3
    mozo
    mozo-gtk3
    pluma
    pluma-gtk3
    python2-caja
    python2-caja-gtk3
    galculator
    obex-data-server
    blueman
)

DISABLED=(gnome-main-menu)

BUILD_ORDER=("${CORE[@]}" "${EXTRA[@]}")

MATE_VER=1.9
BASEDIR=$(dirname $(readlink -f ${0}))
REPODIR="/var/local/mate-unstable/${MATE_VER}"

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
    echo "      clean       Remove MATE packages from /var/cache/pacan/pkg."
    echo "      repo        Create a package repository in '${HOME}/mate/'"
    echo "      sync        'rsync' a repo to ${RSYNC_UPSTREAM}."
    echo
    echo "Each of the tasks above run automatically and operate over the entire"
    echo "package tree."
}

function config_builder() {
    if [ "${MACHINE}" == "x86_64" ]; then
        ln -s /usr/bin/archbuild /usr/local/bin/mate-unstable-i686-build 2>/dev/null
        ln -s /usr/bin/archbuild /usr/local/bin/mate-unstable-x86_64-build 2>/dev/null
    elif  [ "${MACHINE}" == "i686" ]; then
        ln -s /usr/bin/archbuild /usr/local/bin/mate-unstable-i686-build 2>/dev/null
    fi
    rm /usr/local/bin/mate-unstablepkg 2>/dev/null

    # Augment /usr/share/devtools/pacman-extra.conf
    cp pacman-mate-unstable.conf /usr/share/devtools/pacman-mate-unstable.conf
}

function repo_init() {
    # Remove any existing repositories and create empty ones.
    rm -rf /var/local/mate-unstable/*
    for INIT_ARCH in i686 x86_64
    do
        mkdir -p ${REPODIR}/${INIT_ARCH}
        touch ${REPODIR}/${INIT_ARCH}/mate-unstable.db
    done
}

function repo_update() {
    local CHROOT_PLAT="${1}"
    if [ ! -d ${REPODIR}/${CHROOT_PLAT} ]; then
        mkdir -p ${REPODIR}/${CHROOT_PLAT}
    fi
    repo-add -q --nocolor --new ${REPODIR}/${CHROOT_PLAT}/mate-unstable.db.tar.gz ${REPODIR}/${CHROOT_PLAT}/*.pkg.tar.xz 2>/dev/null
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
    darkhttpd /var/local/mate-unstable/ --port 8089 --daemon --log /tmp/mate-unstable-darkhttpd.log --pidfile /tmp/mate-unstable-darkhttpd.pid
}

# Build packages that are not at the current version.
function tree_build() {
    local PKG=${1}
    local PKGBASE=$(echo ${PKG} | sed 's/-gtk3//')

    echo "Building ${PKG}"
    cd ${PKG}
    # If there is a git clone check the revision.
    if [ -f ${PKGBASE}/FETCH_HEAD ]; then
        echo " - Fetching revision from git"
        # git version
        local _ver=$(grep -E ^_ver PKGBUILD | cut -f2 -d'=')
        cd ${PKGBASE}
        git fetch
        local PKGBUILD_VER=$(printf "%s.%s.%s" "${_ver}" "$(git log -1 --format=%cd --date=short | tr -d -)" "$(git rev-list --count HEAD)")
        cd ..
    else
        # pacakge version
        local PKGBUILD_VER=$(grep -E ^pkgver PKGBUILD | cut -f2 -d'=' | head -n1)
    fi

    local PKGBUILD_REL=$(grep -E ^pkgrel PKGBUILD | cut -f2 -d'=')
    local PKGBUILD=${PKGBUILD_VER}-${PKGBUILD_REL}
    local TEST_ANY=$(grep "^arch=" PKGBUILD | grep any)
    if [ -n "${TEST_ANY}" ]; then
        if [ "${MACHINE}" == "i686" ] || [ "${MACHINE}" == "x86_64" ]; then
            local CHROOT_ARCHS=(i686)
        fi
    else
        if [ "${MACHINE}" == "i686" ] || [ "${MACHINE}" == "x86_64" ]; then
            local CHROOT_ARCHS=(i686 x86_64)
        fi
    fi

    for CHROOT_ARCH in ${CHROOT_ARCHS[@]};
    do
        if [ "${PKG}" == "caja-extensions" ]; then
            PKG_CHECK="caja-share"
        elif [ "${PKG}" == "caja-extensions-gtk3" ]; then
            PKG_CHECK="caja-share-gtk3"
        else
            PKG_CHECK="${PKG}"
        fi

        if [ -n "${TEST_ANY}" ]; then
            echo " - Looking for ${PKG_CHECK}-${PKGBUILD}-any.pkg.tar.xz"
            EXIST=$(ls -1 ${PKG_CHECK}-${PKGBUILD}-any.pkg.tar.xz 2>/dev/null)
            local RET=$?
        else
            echo " - Looking for ${PKG_CHECK}-${PKGBUILD}-${CHROOT_ARCH}.pkg.tar.xz"
            EXIST=$(ls -1 ${PKG_CHECK}-${PKGBUILD}-${CHROOT_ARCH}.pkg.tar.xz 2>/dev/null)
            local RET=$?
        fi

        if [ ${RET} -ne 0 ]; then
            echo " - Did not find built packages for ${PKG}."
            echo " - Building ${PKG}"
            mate-unstable-${CHROOT_ARCH}-build
            if [ $? -ne 0 ]; then
                echo " - Failed to build ${PKG} for ${CHROOT_ARCH}. Stopping here."
                httpd_stop
                exit 1
            fi
        else
            echo " - Found matching build for ${PKG}."
            if [ -n "${TEST_ANY}" ]; then
                echo " - ${PKG}-${PKGBUILD}-any is current"
            else
                echo " - ${PKG}-${PKGBUILD}-${CHROOT_ARCH} is current"
            fi
        fi

        echo " - Adding '${PKG}' to [mate-unstable]"
        if [ -n "${TEST_ANY}" ]; then
            if [ "${MACHINE}" == "i686" ] || [ "${MACHINE}" == "x86_64" ]; then
                if [ "${PKG}" == "caja-extensions" ] || [ "${PKG}" == "caja-extensions-gtk3" ]; then
                    cp -a caja*-any.pkg.tar.xz ${REPODIR}/i686/ 2>/dev/null
                    cp -a caja*-any.pkg.tar.xz ${REPODIR}/x86_64/ 2>/dev/null
                else
                    cp -a ${PKG}*-any.pkg.tar.xz ${REPODIR}/i686/ 2>/dev/null
                    cp -a ${PKG}*-any.pkg.tar.xz ${REPODIR}/x86_64/ 2>/dev/null
                fi
                repo_update i686
                repo_update x86_64
            fi
        else
            if [ "${PKG}" == "caja-extensions" ] || [ "${PKG}" == "caja-extensions-gtk3" ]; then
                cp -a caja*-${CHROOT_ARCH}.pkg.tar.xz ${REPODIR}/${CHROOT_ARCH}/ 2>/dev/null          
            else
                cp -a ${PKG}*-${CHROOT_ARCH}.pkg.tar.xz ${REPODIR}/${CHROOT_ARCH}/ 2>/dev/null
            fi
            repo_update ${CHROOT_ARCH}
        fi
    done
    echo
}

# Check for new upstream releases.
function tree_check() {
    local PKG=${1}

    if [ "${PKG}" == "python2-caja" ]; then
        UPSTREAM_PKG="python-caja"
    else
        UPSTREAM_PKG="${PKG}"
    fi

    if [ ! -f /tmp/${MATE_VER}_SUMS ]; then
        echo " - Downloading MATE ${MATE_VER} SHA1SUMS"
        wget -c -q http://pub.mate-desktop.org/releases/${MATE_VER}/SHA1SUMS -O /tmp/${MATE_VER}_SUMS
    fi
    echo " - Checking ${UPSTREAM_PKG}"
    IS_UPSTREAM=$(grep -E ${UPSTREAM_PKG}-[0-9]. /tmp/${MATE_VER}_SUMS)
    if [ -n "${IS_UPSTREAM}" ]; then
        local UPSTREAM_TARBALL=$(grep [0-9a-f]\ .${UPSTREAM_PKG}\-[0-9] /tmp/${MATE_VER}_SUMS | cut -c43- | tail -n1)
        local UPSTREAM_SHA1=$(grep [0-9a-f]\ .${UPSTREAM_PKG}\-[0-9] /tmp/${MATE_VER}_SUMS | cut -c1-40 | tail -n1)
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

# `rsync` repo upstream.
function tree_sync() {
    echo "Action : sync"
    # Modify this accordingly.
    local RSYNC_UPSTREAM="mate@mate.flexion.org::mate-${MATE_VER}"
    chown -R 1000:100 ${REPODIR}
    rsync -av --delete --progress ${REPODIR}/ "${RSYNC_UPSTREAM}/"
}

# `rsync` repo upstream.
function tree_clean() {
    echo "Action : clean"
    rm -fv /var/cache/pacman/pkg/atril*
    rm -fv /var/cache/pacman/pkg/*caja*
    rm -fv /var/cache/pacman/pkg/engrampa*
    rm -fv /var/cache/pacman/pkg/eom*
    rm -fv /var/cache/pacman/pkg/marco*
    rm -fv /var/cache/pacman/pkg/*mate*
    rm -fv /var/cache/pacman/pkg/mozo*
    rm -fv /var/cache/pacman/pkg/pluma*
    rm -fv */*.pkg.tar.xz
    rm -fv */*.log
    rm -rfv ${REPODIR}/*
}

function tree_run() {
    local ACTION=${1}
    echo "Action : ${ACTION}"

    config_builder
    repo_init
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
elif [ "${TASK}" == "clean" ] ||
     [ "${TASK}" == "sync" ]; then
    tree_${TASK}
else
    usage
    exit 1
fi

# Clean up.
rm -f /tmp/*_SUMS 2>/dev/null

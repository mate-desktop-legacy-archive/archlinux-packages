#!/usr/bin/env bash

TEST_DEVTOOLS=$(pacman -Qq devtools 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "ERROR! You must install 'devtools'."
    exit 1
fi

MACHINE=$(uname -m)
if [ "${MACHINE}" != "x86_64" ]; then
    echo "ERROR! This script must be run on x86_64 hardware."
    exit 1
fi

# http://wiki.mate-desktop.org/status:1.10
BUILD_ORDER=(
    #mate-common
    #mate-desktop
    #libmatekbd
    #libmateweather
    #mate-icon-theme
    #caja
    #mate-polkit
    #marco
    #mate-settings-daemon
    #mate-session-manager
    #mate-menus
    #mate-panel
    #mate-media
    #mate-backgrounds
    #mate-themes
    #mate-notification-daemon
    #mate-control-center
    #gnome-main-menu
    #mate-screensaver
    #engrampa
    #mate-power-manager
    #mate-system-monitor
    #atril
    #caja-extensions
    #mate-applets
    #eom
    #mate-icon-theme-faenza
    #mozo
    #mate-netbook
    #mate-netspeed
    #mate-sensors-applet
    #mate-terminal
    #pluma
    #mate-user-share
    mate-utils             # Doesn't build
    #python2-caja
    #galculator
    #blueman
)

MATE_VER=1.10
BASEDIR=$(dirname $(readlink -f ${0}))
STAMP=$(date +%y.%j.%H%M)
STAMP="14.121.1234"
REPO="mate-unstable-gtk3-${STAMP}"
REPODIR="${HOME}/public_html/${REPO}/${MATE_VER}"
TMPDIR="${HOME}/tmp"
EMAIL_TO=$(tr a-zA-Z n-za-mN-ZA-M <<< znegva@syrkvba.bet)

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
    echo
    echo "Each of the tasks above run automatically and operate over the entire"
    echo "package tree."
}

function repo_init() {
    # Remove any existing repositories and create empty ones.
    #rm -rf ${REPODIR}
    for INIT_ARCH in i686 x86_64
    do
        mkdir -p ${REPODIR}/${INIT_ARCH}/logs
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

# Build packages that are not at the current version.
function tree_build() {
    local PKG=${1}
    echo "Building ${PKG}"
    cd ${PKG}

    # Clean existing logs and packages
    #rm -f *.log*
    #rm -f *.pkg.tar.xz

    # If there is a git clone check the revision.
    if [ -f ${PKG}/FETCH_HEAD ]; then
        echo " - Fetching revision from git"
        # git version
        local _ver=$(grep -E ^_ver PKGBUILD | cut -f2 -d'=')
        cd ${PKG}
        git fetch
        local PKGBUILD_VER="${_ver}.*.$(git rev-parse --short master)"
        cd ..
    else
        # pacakge version
        local PKGBUILD_VER=$(grep -E ^pkgver PKGBUILD | cut -f2 -d'=' | head -n1)
    fi

    local PKGBUILD_REL=$(grep -E ^pkgrel PKGBUILD | cut -f2 -d'=')
    local PKGBUILD=${PKGBUILD_VER}-${PKGBUILD_REL}
    local TEST_ANY=$(grep "^arch=" PKGBUILD | grep any)

    for CHROOT_ARCH in i686 x86_64; do
        echo " - Building ${PKG}"
        if [ "${PKG}" == "mate-common" ]; then
            # Create a new chroot when building mate-common
            sudo makechrootpkg -c -n -r /var/lib/archbuild/extra-${CHROOT_ARCH} -- --install
            local BUILD_RET=$?
        else
            # Update the existing chroot for every other package.
            sudo makechrootpkg -u -n -r /var/lib/archbuild/extra-${CHROOT_ARCH} -- --install
            local BUILD_RET=$?
        fi

        # If "bad stuff" happened, stop here.
        if [ ${BUILD_RET} -ne 0 ]; then
            echo " - Failed to build ${PKG} for ${CHROOT_ARCH}. Stopping here."
            cat -v *-${CHROOT_ARCH}-build.log | mail -s "Failed building ${PKG}" ${EMAIL_TO}
            exit 1
        fi

        echo " - Adding '${PKG}' to [mate-unstable]"
        if [ -n "${TEST_ANY}" ]; then
            cp -av *-any.pkg.tar.xz ${REPODIR}/${CHROOT_ARCH}/
        else
            cp -av *-${CHROOT_ARCH}.pkg.tar.xz ${REPODIR}/${CHROOT_ARCH}/
        fi

        # Copy the build logs for posterity.
        # Yes 'any' and arch specific are required all the time.
        cp -a *-any*.log ${REPODIR}/${CHROOT_ARCH}/logs 2>/dev/null
        cp -a *-${CHROOT_ARCH}*.log ${REPODIR}/${CHROOT_ARCH}/logs 2>/dev/null

        repo_update ${CHROOT_ARCH}
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

    if [ ! -f ${TMPDIR}/${MATE_VER}_SUMS ]; then
        echo " - Downloading MATE ${MATE_VER} SHA1SUMS"
        wget -c -q http://pub.mate-desktop.org/releases/${MATE_VER}/SHA1SUMS -O ${TMPDIR}/${MATE_VER}_SUMS
    fi
    echo " - Checking ${UPSTREAM_PKG}"
    IS_UPSTREAM=$(grep -E ${UPSTREAM_PKG}-[0-9]. ${TMPDIR}/${MATE_VER}_SUMS)
    if [ -n "${IS_UPSTREAM}" ]; then
        local UPSTREAM_TARBALL=$(grep [0-9a-f]\ .${UPSTREAM_PKG}\-[0-9] ${TMPDIR}/${MATE_VER}_SUMS | cut -c43- | tail -n1)
        local UPSTREAM_SHA1=$(grep [0-9a-f]\ .${UPSTREAM_PKG}\-[0-9] ${TMPDIR}/${MATE_VER}_SUMS | cut -c1-40 | tail -n1)
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

function tree_run() {
    local ACTION=${1}
    echo "Action : ${ACTION}"

    repo_init
    for PKG in ${BUILD_ORDER[@]};
    do
        cd ${BASEDIR}
        tree_${ACTION} ${PKG}
    done
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

if [ "${TASK}" == "build" ] || [ "${TASK}" == "check" ]; then
    tree_run ${TASK}
else
    usage
    exit 1
fi

# Clean up.
rm -f ${TMPDIR}/*_SUMS 2>/dev/null

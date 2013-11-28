#!/usr/bin/env bash

AUR_BUILD_ORDER=(
    aur/libindicator
    aur/system-tools-backends
    aur/liboobs
    aur/libxnvctrl
    #aur/python2-exiv2
)

# http://wiki.mate-desktop.org/status:1.8
MATE_BUILD_ORDER=(	
	mate-common
	mate-desktop
	libmatekbd
	libmateweather
	mate-icon-theme
	mate-dialogs
	caja
	mate-polkit
	marco
	mate-settings-daemon-gstreamer
	mate-settings-daemon-pulseaudio
	mate-session-manager
	mate-menus
	mate-panel
	mate-backgrounds
	mate-themes
	mate-notification-daemon
	mate-control-center
	mate-screensaver
	engrampa
	mate-media
	mate-power-manager
	mate-system-monitor	
	atril
	caja-dropbox
	caja-extensions
	mate-applets
	mate-bluetooth
	mate-calc	
	eom
	mate-icon-theme-faenza
	mate-indicator-applet
	mozo
	mate-netbook
	mate-netspeed
	mate-sensors-applet
	mate-system-tools
	mate-terminal
	pluma
	mate-user-share
	mate-utils
	python-caja
)

COMMUNITY_BUILD_ORDER=(
    community/mate-applet-lockkeys
    community/mate-applet-softupd
    community/mate-applet-streamer
    community/mate-disk-utility
    community/mate-color-manager
    community/mate-mplayer
    community/mate-nettool
    community/variety
    #community/mintmenu
)

BUILD_ORDER=( ${AUR_BUILD_ORDER[@]} ${MATE_BUILD_ORDER[@]} ${COMMUNITY_BUILD_ORDER[@]})
BUILD_ORDER=( ${AUR_BUILD_ORDER[@]} ${MATE_BUILD_ORDER[@]} )
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
    echo "      audit       Show which packages remain to be built."
    echo "      aur         Upload 'src' packages to the AUR."
    echo "      build       Build MATE packages."
    echo "      check       Check upstream for new source tarballs."
    echo "      clean       Clean source directories using 'make maintainer-clean'."
    echo "      delete      Delete Arch Linux 'pkg.tar.xz' binary package files."
    echo "      purge       Purge source tarballs, 'src' and 'pkg' directories."
    echo "      repo        Create a package repository in '${HOME}/mate/'"
    echo "      sync        'rsync' a repo to ${RSYNC_UPSTREAM}."
    echo "      uninstall   Uninstall MATE packages and dependencies."
    echo
    echo "Each of the tasks above run automatically and operate over the entire"
    echo "package tree."
}

# Make an .install file.
# OK, this is as ugly as hell but it works.
# Skip past this section and look how nice everything else is ;-)
function make_install_file() {
    local INSTALL_FILE="${1}"
    echo "post_install() {" > ${INSTALL_FILE}
    if [ ${INSTALL_SCHEMA} -eq 1 ]; then
        echo "    glib-compile-schemas /usr/share/glib-2.0/schemas/" >> ${INSTALL_FILE}
    fi
    if [ ${INSTALL_MIME} -eq 1 ]; then
        echo "    update-mime-database /usr/share/mime/ > /dev/null" >> ${INSTALL_FILE}
    fi
    if [ ${INSTALL_ICON} -eq 1 ]; then
        for ICON_DIR in ${ICON_ARRAY[@]}; do
            echo "    gtk-update-icon-cache -q -t -f /usr/share/icons/${ICON_DIR}" >> ${INSTALL_FILE}
        done
    fi
    if [ ${INSTALL_DESKTOP} -eq 1 ]; then
        echo "    update-desktop-database -q" >> ${INSTALL_FILE}
    fi
    echo "}" >> ${INSTALL_FILE}
    echo >> ${INSTALL_FILE}
    echo "pre_upgrade() {" >> ${INSTALL_FILE}
    echo "    pre_remove" >> ${INSTALL_FILE}
    echo "}" >> ${INSTALL_FILE}
    echo >> ${INSTALL_FILE}
    echo "post_upgrade() {" >> ${INSTALL_FILE}
    echo "    post_install" >> ${INSTALL_FILE}
    echo "}" >> ${INSTALL_FILE}
    echo >> ${INSTALL_FILE}
    echo "pre_remove() {" >> ${INSTALL_FILE}
    if [ ${INSTALL_SCHEMA} -eq 1 ]; then
        echo "    glib-compile-schemas /usr/share/glib-2.0/schemas/" >> ${INSTALL_FILE}
    else
        echo "    :" >> ${INSTALL_FILE}
    fi
    echo "}" >> ${INSTALL_FILE}
    echo >> ${INSTALL_FILE}
    echo "post_remove() {" >> ${INSTALL_FILE}
    local PASS=$((${INSTALL_MIME} + ${INSTALL_ICON} + ${INSTALL_DESKTOP}))
    if [ ${PASS} -eq 0 ]; then
        echo "    :" >> ${INSTALL_FILE}
    else
        if [ ${INSTALL_MIME} -eq 1 ]; then
            echo "    update-mime-database /usr/share/mime/ > /dev/null" >> ${INSTALL_FILE}
        fi
        if [ ${INSTALL_ICON} -eq 1 ]; then
            for ICON_DIR in ${ICON_ARRAY[@]}; do
                echo "    gtk-update-icon-cache -q -t -f /usr/share/icons/${ICON_DIR}" >> ${INSTALL_FILE}
            done
        fi
        if [ ${INSTALL_DESKTOP} -eq 1 ]; then
            echo "    update-desktop-database -q" >> ${INSTALL_FILE}
        fi
    fi
    echo "}" >> ${INSTALL_FILE}
}

# Determine is a .install file needs creation, updating or deletion.
function update_install_file() {
    local PKG=${1}
    local INSTALL_REQUIRED=$((${INSTALL_SCHEMA} + ${INSTALL_MIME} + ${INSTALL_ICON} + ${INSTALL_DESKTOP}))
    if [ ${INSTALL_REQUIRED} -ge 1 ]; then
        local INSTALL_FILE=`basename ${PKG}`.install

        if [ -f ${INSTALL_FILE} ]; then
            echo "    Generating /tmp/${INSTALL_FILE}"
            make_install_file /tmp/${INSTALL_FILE}
            NEW_SUM=$(md5sum /tmp/${INSTALL_FILE} | cut -d' ' -f1)
            CUR_SUM=$(md5sum ${INSTALL_FILE} | cut -d' ' -f1)
            if [ "${NEW_SUM}" != "${CUR_SUM}" ]; then
                echo "    Review /tmp/${INSTALL_FILE} as it differs."
            else
                echo "    Files are identical, removing /tmp/${INSTALL_FILE}"
                rm -f /tmp/${INSTALL_FILE}
            fi
        else
            echo "    Creating ${INSTALL_FILE}"
            make_install_file ${INSTALL_FILE}
        fi

        local TEST_INSTALL=$(grep -E ^install= PKGBUILD)
        if [ $? -ne 0 ]; then
            echo "    Missing 'install=${INSTALL_FILE}' in PKGBUILD."
        fi
    else
        if [ -f *.install ]; then
            echo "    Detected a custom '.install' file, please review it."
        fi
    fi
}

# Show packages that are not yet built.
function tree_audit() {
    local PKG=${1}
    cd ${PKG}
    local PKGBUILD_VER=$(grep -E ^pkgver PKGBUILD | cut -f2 -d'=')
    local PKGBUILD_REL=$(grep -E ^pkgrel PKGBUILD | cut -f2 -d'=')
    local PKGBUILD=${PKGBUILD_VER}-${PKGBUILD_REL}
    local EXISTS=$(ls -1 *${PKGBUILD}*.pkg.tar.xz 2>/dev/null)
    echo " - ${PKG}"
    if [ -z "${EXISTS}" ]; then
        echo "    Requires building."
    elif [ -d pkg ]; then
        INSTALL_SCHEMA=0
        INSTALL_ICON=0
        INSTALL_MIME=0
        INSTALL_DESKTOP=0
        local FIND_A=$(find pkg/ -name *.a)
        if [ -n "${FIND_A}" ]; then
            echo "    Contains .a files, delete them via 'package()' in PKGBUILD."
            echo "    ${FIND_A}"
        fi
        local FIND_LA=$(find pkg/ -name *.la)
        if [ -n "${FIND_LA}" ]; then
            echo "    Contains .la files, add '!libtool' to 'options' in PKGBUILD."
            echo "    ${FIND_LA}"
        fi
        if [ -d pkg/*/usr/sbin ]; then
            echo "    Detected '/usr/sbin' add '--sbindir=/usr/bin' to 'build()' in PKGBUILD."
        fi
        if [ -d pkg/*/usr/libexec ]; then
            echo "    Detected '/usr/libexec' add '--libexecdir=/usr/lib/${pkgname}' to 'build()' in PKGBUILD."
        fi
        if [ -d pkg/*/usr/share/glib-2.0/schemas ]; then
            echo "    Contains glib-2.0 schemas, '.install' will auto-update."
            INSTALL_SCHEMA=1
        fi
        if [ -d pkg/*/usr/share/icons ]; then
            echo "    Contains icons, '.install' will auto-update."
            declare -a ICON_ARRAY=()
            for ICON in pkg/*/usr/share/icons/*
            do
                if [ -d ${ICON} ]; then
                    ICON_NAME=`basename ${ICON}`
                    ICON_ARRAY=("${ICON_ARRAY[@]}" "${ICON_NAME}")
                fi
            done
            INSTALL_ICON=1
        fi
        if [ -d pkg/*/usr/share/mime ]; then
            echo -n "    Contains MIME types, "
            local TEST_MIME=$(grep shared-mime-info PKGBUILD)
            if [ $? -eq 0 ]; then
                echo "no action required."
            else
                echo "add 'shared-mime-info' to PKGBUILD 'depends'."
            fi
            INSTALL_MIME=1
        fi
        if [ -d pkg/*/usr/share/applications ]; then
            echo -n "    Contains .desktop files, "
            local TEST_DESKTOP=$(grep desktop-file-utils PKGBUILD)
            if [ $? -eq 0 ]; then
                echo "no action required."
            else
                echo "add 'desktop-file-utils' to PKGBUILD 'depends'."
            fi
            INSTALL_DESKTOP=1
        fi
        update_install_file ${PKG}
    fi
}

# Make 'src' packages and upload them to the AUR
function tree_aur() {
    local PKG=${1}
    cd ${PKG}

    local INSTALLED=$(pacman -Q `basename ${PKG}` 2>/dev/null | cut -f2 -d' ')
    local PKGBUILD_VER=$(grep -E ^pkgver PKGBUILD | cut -f2 -d'=')
    local PKGBUILD_REL=$(grep -E ^pkgrel PKGBUILD | cut -f2 -d'=')
    local PKGBUILD=${PKGBUILD_VER}-${PKGBUILD_REL}
    local EXISTS=$(ls -1 *${PKGBUILD}*.src.tar.gz 2>/dev/null)

    if [ -z "${EXISTS}" ]; then
        echo " - Burping ${PKG}"
        # Guess a category
        if [[ "${PKG}" == *lib* ]] || [[ "${PKG}" == *python* ]]; then
            local CAT="--category=lib"
        elif [[ "${PKG}" == *mate* ]]; then
            local CAT="--category=x11"
        else
            local CAT=""
        fi

        makepkg -Sfd --noconfirm --needed

        # Attempt an auto upload to the AUR.
        # https://github.com/falconindy/burp
        if [ -f ${HOME}/.config/burp/burp.conf ]; then
            grep flexiondotorg ${HOME}/.config/burp/burp.conf
            if [ $? -eq 0 ]; then            
                burp --verbose ${CAT} `ls -1 *${PKGBUILD}*.src.tar.gz`
                if [ $? -ne 0 ]; then
                    echo ${PKG} >> /tmp/aur_fails.txt
                fi
            fi
        fi
    fi
}

# Build packages that are not at the current version.
function tree_build() {
    local PKG=${1}
    cd ${PKG}
    local INSTALLED=$(pacman -Q `basename ${PKG}` 2>/dev/null | cut -f2 -d' ')
    local PKGBUILD_VER=$(grep -E ^pkgver PKGBUILD | cut -f2 -d'=')
    local PKGBUILD_REL=$(grep -E ^pkgrel PKGBUILD | cut -f2 -d'=')
    local PKGBUILD=${PKGBUILD_VER}-${PKGBUILD_REL}
    local EXISTS=$(ls -1 *${PKGBUILD}*.pkg.tar.xz 2>/dev/null)

    if [ "${PKG}" == "mate-settings-daemon-pulseaudio" ]; then
        sudo pacman -Rsdd --noconfirm mate-settings-daemon-gstreamer
        sudo pacman -Rsdd --noconfirm mate-media-gstreamer
        sudo pacman -Rsdd --noconfirm mate-settings-daemon
        sudo pacman -Rsdd --noconfirm mate-media
    elif [ "${PKG}" == "mate-settings-daemon-gstreamer" ]; then
        sudo pacman -Rsdd --noconfirm mate-settings-daemon-pulseaudio
        sudo pacman -Rsdd --noconfirm mate-media-pulseaudio
        sudo pacman -Rsdd --noconfirm mate-settings-daemon
        sudo pacman -Rsdd --noconfirm mate-media
    fi

    if [ -z "${EXISTS}" ]; then
        echo " - Building ${PKG}"
        if [ $(id -u) -eq 0 ]; then
            makepkg -fs --noconfirm --needed --log --asroot
        else
            makepkg -fs --noconfirm --needed --log
        fi

        if [ $? -ne 0 ]; then
            echo " - Failed to build ${PKG}. Stopping here."
            exit 1
        else
            sudo makepkg -i --noconfirm --asroot
        fi
    else
        if [ "${INSTALLED}" != "${PKGBUILD}" ]; then
            sudo makepkg -i --noconfirm --asroot
        fi
    fi
}

# Check for new upstream releases.
function tree_check() {
    local PKG=${1}

    # Account for version differences.
    if [ "${PKG}" == "caja-dropbox" ]; then
        local CHECK_VER="1.4"
    else
        local CHECK_VER="${MATE_VER}"
    fi

    # Skip duplicate packages.
    if [ "${PKG}" == "mate-settings-daemon-gstreamer" ] || [ "${PKG}" == "mate-media-gstreamer" ]; then
        return
    fi

    case ${PKG} in
        "python2-caja") UPSTREAM_PKG="python-caja";;
        "mate-settings-daemon-gstreamer") UPSTREAM_PKG="mate-settings-daemon";;
        "mate-settings-daemon-pulseaudio") UPSTREAM_PKG="mate-settings-daemon";;
        "mate-media-gstreamer") UPSTREAM_PKG="mate-media";;
        "mate-media-pulseaudio") UPSTREAM_PKG="mate-media";;
        *) UPSTREAM_PKG="${PKG}"
    esac

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

# Clean the sources using `make maintainer-clean`.
function tree_clean() {
    local PKG=${1}
    for SRC in ${PKG}/src/*
    do
        if [ -f ${SRC}/Makefile ]; then
            echo " - Cleaning ${SRC}"
            cd ${SRC}
            make maintainer-clean &> /dev/null
        fi
    done
}

# Delete all binary package files.
function tree_delete() {
    local PKG=${1}
    for PACKAGE in ${PKG}/*.pkg.tar.xz
    do
        echo " - Deleting ${PACKAGE}"
        rm -f ${PACKAGE}
    done
}

# Purge source tarballs, `src` and `pkg` directories.
function tree_purge() {
    local PKG=${1}
    # Remove all source tarballs, don't bother checking versions just ditch them all.
    for TARBALL in ${PKG}/*.tar.{b,g,x}z*
    do
        if [ -f ${TARBALL} ] && [[ "${TARBALL}" != *pkg* ]]; then
            echo " - Deleting ${TARBALL}"
            rm -f ${TARBALL}
        fi
    done
    # Remove 'src' and 'pkg' directories created by `makepkg`.
    if [ -d ${PKG}/src ]; then
        echo " - Deleting ${PKG}/src"
        rm -rf ${PKG}/src
    fi
    if [ -d ${PKG}/pkg ]; then
        echo " - Deleting ${PKG}/pkg"
        rm -rf ${PKG}/pkg
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
        cd ${BASEDIR}/${PKG}
        local PKGBUILD_VER=$(grep -E ^pkgver PKGBUILD | cut -f2 -d'=')
        local PKGBUILD_REL=$(grep -E ^pkgrel PKGBUILD | cut -f2 -d'=')
        local PKGBUILD=${PKGBUILD_VER}-${PKGBUILD_REL}
        local NEWEST=$(ls -1 *${PKGBUILD}*.pkg.tar.xz 2>/dev/null)
        if [ -f ${NEWEST} ]; then
            cp -v ${NEWEST} ${HOME}/${MATE_VER}/${CARCH}/
        fi
    done

    # Simulate 'makepkg --sign'
    KEY_TEST=`gpg --list-secret-key | grep FFEE1E5C`
    if [ $? -eq 0 ]; then
	cd ${HOME}/${MATE_VER}/${CARCH}
        for XZ in *.xz
        do
            echo " - Signing ${XZ}"
            gpg --detach-sign -u 0xFFEE1E5C ${XZ}
        done
    fi

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

# Uninstall MATE packages and orphans from the system.
function tree_uninstall() {
    echo "Action : uninstall"
    local INSTALLED_PKGS=$(pacman -Qq)
    local UNINSTALL_PKGS=""
    cd ${BASEDIR}
    for PKG in ${BUILD_ORDER[@]};
    do
        PKG=$(basename ${PKG})
        if [ -n "$(echo ${INSTALLED_PKGS} | grep ${PKG})" ]; then
            UNINSTALL_PKGS="${UNINSTALL_PKGS} ${PKG}"
        fi
    done
    sudo pacman -Rs --noconfirm ${UNINSTALL_PKGS}
}

function tree_run() {
    local ACTION=${1}
    echo "Action : ${ACTION}"

    if [ "${ACTION}" == "check" ]; then
        local ORDER=( ${MATE_BUILD_ORDER[@]} )
    else
        local ORDER=( ${BUILD_ORDER[@]} )
    fi

    for PKG in ${ORDER[@]};
    do
        cd ${BASEDIR}
        tree_${ACTION} ${PKG}
    done
}

rm -f /tmp/aur_fails.txt 2>/dev/null

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

if [ "${TASK}" == "audit" ] ||
   [ "${TASK}" == "aur" ] ||
   [ "${TASK}" == "build" ] ||
   [ "${TASK}" == "check" ] ||
   [ "${TASK}" == "clean" ] ||
   [ "${TASK}" == "delete" ] ||
   [ "${TASK}" == "purge" ]; then
    tree_run ${TASK}
elif [ "${TASK}" == "repo" ] || [ "${TASK}" == "sync" ] || [ "${TASK}" == "uninstall" ]; then
    tree_${TASK}
else
    usage
    exit 1
fi

# Clean up.
rm -f /tmp/*_SUMS 2>/dev/null

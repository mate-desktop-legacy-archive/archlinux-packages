#!/usr/bin/env bash

MATE_VER=1.10
TARGET="staging"
ACTION="build"
ACTION="move"
MACHINE=$(uname -m)

TEST_DEVTOOLS=$(pacman -Qq devtools 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "ERROR! You must install 'devtools'."
    exit 1
fi

echo "Configure packager"
echo 'PACKAGER="Martin Wimpress <code@flexion.org>"' > "${HOME}"/.makepkg.conf
echo 'GPGKEY="0864983E"' >> "${HOME}"/.makepkg.conf

echo "Checkout svn-community"
if [ ! -d "${HOME}"/BitSync/Source/archlinux.org/svn-community ]; then
    mkdir -p "${HOME}"/BitSync/Source/archlinux.org
    cd "${HOME}"/BitSync/Source/archlinux.org
    svn checkout -N svn+ssh://svn-community@nymeria.archlinux.org/srv/repos/svn-community/svn svn-community
    cd svn-community
else
    cd "${HOME}"/BitSync/Source/archlinux.org/svn-community
    svn update
fi

# http://wiki.mate-desktop.org/status:1.10
CORE=(
    #mate-common
    #mate-desktop
    #libmatekbd
    #libmatemixer
    #libmateweather
    #mate-icon-theme
    #caja
    #caja-gtk3
    #mate-polkit
    #marco
    #marco-gtk3
    #mate-settings-daemon
    #mate-settings-daemon-gtk3
    #mate-session-manager
    #mate-session-manager-gtk3
    #mate-menus
    #mate-panel
    #mate-panel-gtk3
    #mate-backgrounds
    #mate-themes
    #mate-notification-daemon
    #mate-control-center
    #mate-control-center-gtk3
    #mate-screensaver
    #mate-screensaver-gtk3
    #mate-media
    #mate-media-gtk3
    #mate-power-manager
    #mate-power-manager-gtk3
    #mate-system-monitor
)

EXTRA=(
    #atril
    #atril-gtk3
    #caja-extensions
    #caja-extensions-gtk3
    #engrampa
    #engrampa-gtk3
    #eom
    #eom-gtk3
    #mate-applets
    #mate-applets-gtk3
    #mate-icon-theme-faenza
    #mate-netbook
    #mate-netbook-gtk3
    #mate-netspeed
    #mate-netspeed-gtk3
    #mate-sensors-applet
    #mate-sensors-applet-gtk3
    #mate-terminal
    #mate-terminal-gtk3
    #mate-user-guide - not released
    #mate-user-share
    #mate-user-share-gtk3
    #mate-utils
    #mate-utils-gtk3
    mozo
    #mozo-gtk3
    #pluma
    #pluma-gtk3
    #python2-caja
    #python2-caja-gtk3
)

AUR_EXTRA=(
    caja-dropbox
    mate-indicator-applet
)

OTHER=(
    galculator
    gnome-main-menu
    obex-data-server
    blueman
)

BUILD_ORDER=("${CORE[@]}" "${EXTRA[@]}")

function pkg_builder() {
    local PKG=${1}
    local REPO="${2}"
    local PKGBASE=$(echo ${PKG} | sed 's/-gtk3//')

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
        #local PKGBUILD_VER=$(grep -E ^pkgver PKGBUILD | cut -f2 -d'=' | head -n1)
        local POINT_VER=$(grep -E ^pkgver PKGBUILD | cut -d'.' -f2)
        local PKGBUILD_VER="${MATE_VER}.${POINT_VER}"
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

    local PUBLISH=0
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
            echo " - Building ${PKG}"
            sudo ${REPO}-${CHROOT_ARCH}-build
            if [ $? -ne 0 ]; then
                echo " - Failed to build ${PKG} for ${CHROOT_ARCH}. Stopping here."
                exit 1
            fi
            local PUBLISH=1
        else
            if [ -n "${TEST_ANY}" ]; then
                echo " - ${PKG}-any is current"
            else
                echo " - ${PKG}-${CHROOT_ARCH} is current"
            fi
        fi
    done

    if [ ${PUBLISH} -eq 1 ]; then
        if [ "${REPO}" == "community" ]; then
            communitypkg
        else
            community-${REPO}pkg
        fi
        ssh flexiondotorg@nymeria.archlinux.org /community/db-update
    fi
}

for PKG_NAME in ${BUILD_ORDER[@]};
do
    # Build
    if [ "${ACTION}" == "build" ]; then

        echo "Building ${PKG_NAME}"
    
        # Update svn
        cd "${HOME}"/BitSync/Source/archlinux.org/svn-community/
        communityco ${PKG_NAME}
        
        if [ ! -d "${PKG_NAME}" ]; then
            mkdir -p "${PKG_NAME}"/{repos,trunk}
            cp -a "${HOME}"/BitSync/Source/archlinux-packages/bitbucket/"${PKG_NAME}"/PKGBUILD "${HOME}"/BitSync/Source/archlinux.org/svn-community/"${PKG_NAME}"/trunk/ 2>/dev/null
            cp -a "${HOME}"/BitSync/Source/archlinux-packages/bitbucket/"${PKG_NAME}"/*.{diff,install,pam,patch} "${HOME}"/BitSync/Source/archlinux.org/svn-community/"${PKG_NAME}"/trunk/ 2>/dev/null
            svn add "${PKG_NAME}"
            svn propset svn:keywords "Id" "${PKG_NAME}"/trunk/PKGBUILD
            TEST_SVN_ID=`head -n1 "${PKG_NAME}"/trunk/PKGBUILD | grep Id`
            RET=$?
            if [ ${RET} -eq 1 ]; then
                echo '# $Id$' > /tmp/svn_id
                cat /tmp/svn_id "${PKG_NAME}"/trunk/PKGBUILD > /tmp/PKGBUILD
                mv /tmp/PKGBUILD "${PKG_NAME}"/trunk/PKGBUILD
            fi
            svn commit -m "Added ${PKG_NAME}"
        else
            cp -a "${HOME}"/BitSync/Source/archlinux-packages/bitbucket/"${PKG_NAME}"/PKGBUILD "${HOME}"/BitSync/Source/archlinux.org/svn-community/"${PKG_NAME}"/trunk/ 2>/dev/null
            cp -a "${HOME}"/BitSync/Source/archlinux-packages/bitbucket/"${PKG_NAME}"/*.{diff,install,pam,patch} "${HOME}"/BitSync/Source/archlinux.org/svn-community/"${PKG_NAME}"/trunk/ 2>/dev/null
            svn commit -m "Updated ${PKG_NAME}"
        fi
    
        cd "${HOME}"/BitSync/Source/archlinux.org/svn-community/"${PKG_NAME}"/trunk/
        if [ "${TARGET}" == "community" ]; then
            pkg_builder "${PKG_NAME}" extra
        elif [ "${TARGET}" == "staging" ]; then
            pkg_builder "${PKG_NAME}" staging
        elif [ "${TARGET}" == "testing" ]; then
            pkg_builder "${PKG_NAME}" testing
        fi
    fi

    # Move package
    if [ "${ACTION}" == "move" ]; then
        ssh flexiondotorg@nymeria.archlinux.org /srv/repos/svn-community/dbscripts/db-move community-staging community "${PKG_NAME}"
    fi
done

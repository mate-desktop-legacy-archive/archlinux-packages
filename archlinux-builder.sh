#!/usr/bin/env bash

TARGET="community"
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
if [ ! -d "${HOME}"/Source/archlinux.org/svn-community ]; then
    mkdir -p "${HOME}"/Source/archlinux.org
    cd "${HOME}"/Source/archlinux.org
    svn checkout -N svn+ssh://svn-community@nymeria.archlinux.org/srv/repos/svn-community/svn svn-community
    cd svn-community
else
    cd "${HOME}"/Source/archlinux.org/svn-community
    svn update
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

function pkg_builder() {
    local PKG="${1}"
    local REPO="${2}"
    local PKGBUILD_VER=$(grep -E ^pkgver PKGBUILD | cut -f2 -d'=' | head -n1)
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
        if [ -n "${TEST_ANY}" ]; then
            EXIST=$(ls -1 ${PKG}*-${PKGBUILD}-any.pkg.tar.xz 2>/dev/null)
            local RET=$?
        else
            EXIST=$(ls -1 ${PKG}*-${PKGBUILD}-${CHROOT_ARCH}.pkg.tar.xz 2>/dev/null)
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
    echo "Building ${PKG_NAME}"
    cd "${HOME}"/Source/archlinux.org/svn-community/
    communityco ${PKG_NAME}

    cd ${PKG_NAME}
    svn commit -m "Remove unneccessary options."

    #if [ ! -d "${PKG_NAME}" ]; then
    #    mkdir -p "${PKG_NAME}"/{repos,trunk}
    #    cp -a "${HOME}"/Source/mate-desktop/archlinux-packages/"${PKG_NAME}"/PKGBUILD "${HOME}"/Source/archlinux.org/svn-community/"${PKG_NAME}"/trunk/ 2>/dev/null
    #    cp -a "${HOME}"/Source/mate-desktop/archlinux-packages/"${PKG_NAME}"/*.{diff,install,pam,patch} "${HOME}"/Source/archlinux.org/svn-community/"${PKG_NAME}"/trunk/ 2>/dev/null
    #    #svn add "${PKG_NAME}"
    #    #svn propset svn:keywords "Id" "${PKG_NAME}"/trunk/PKGBUILD
    #    TEST_SVN_ID=`head -n1 "${PKG_NAME}"/trunk/PKGBUILD | grep Id`
    #    RET=$?
    #    if [ ${RET} -eq 1 ]; then
    #        echo '# $Id$' > /tmp/svn_id
    #        cat /tmp/svn_id "${PKG_NAME}"/trunk/PKGBUILD > /tmp/PKGBUILD
    #        mv /tmp/PKGBUILD "${PKG_NAME}"/trunk/PKGBUILD
    #    fi
    #    #svn commit -m "Added ${PKG_NAME}"
    #else
    #    cp -a "${HOME}"/Source/mate-desktop/archlinux-packages/"${PKG_NAME}"/PKGBUILD "${HOME}"/Source/archlinux.org/svn-community/"${PKG_NAME}"/trunk/ 2>/dev/null
    #    cp -a "${HOME}"/Source/mate-desktop/archlinux-packages/"${PKG_NAME}"/*.{diff,install,pam,patch} "${HOME}"/Source/archlinux.org/svn-community/"${PKG_NAME}"/trunk/ 2>/dev/null
    #    #svn commit -m "Updated ${PKG_NAME}"
    #fi

    # Build
    #cd "${HOME}"/Source/archlinux.org/svn-community/"${PKG_NAME}"/trunk/

    #if [ "${TARGET}" == "community" ]; then
    #    pkg_builder "${PKG_NAME}" extra
    #elif [ "${TARGET}" == "staging" ]; then
    #    pkg_builder "${PKG_NAME}" staging
    #elif [ "${TARGET}" == "testing" ]; then
    #    pkg_builder "${PKG_NAME}" testing
    #fi

    # Move package
    #ssh flexiondotorg@nymeria.archlinux.org /srv/repos/svn-community/dbscripts/db-move community-staging community "${PKG_NAME}"
done

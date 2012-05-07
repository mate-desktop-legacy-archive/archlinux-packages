#!/bin/bash -e
set -e

 #working sometimes :D  I have to code something to handle missing dependencies
 
listofpackages=(
    mate-common
    mate-doc-utils
    mate-corba
    mate-conf
    libmatecomponent
    mate-mime-data
    mate-vfs
    libmate
    libmatecanvas
    libmatecomponentui
    libmatekeyring
    mate-keyring
    libmateui
    libmatenotify
    libmatekbd
    libmateweather
    mate-icon-theme
    mate-dialogs
    mate-desktop
    mate-file-manager
    mate-notification-daemon
    mate-backgrounds
    mate-menus
    mate-window-manager
    mate-polkit
    mate-settings-daemon
    mate-control-center
    mate-panel
    mate-session-manager
    mate-themes
    mate-text-editor
    mate-file-archiver
    mate-document-viewer
    mate-file-manager-sendto
    mate-bluetooth
    mate-power-manager
    python-corba
    python-mate
    python-mate-desktop
    python-caja
    mate-file-manager-open-terminal
    mate-applets
    )
    

for package in ${listofpackages[@]}
	do
	echo " "
	echo "----->  Starting $package build"
	cd $package

	if [ -f *.pkg.tar.xz ];
	then echo "----- $package package already built ^^ I'm checking if it's already installed..."
			if [[  `pacman -Qqe | grep "$package"` ]];
				then installed_pkg_stuff=$(pacman -Q | grep $package);
		#those operations could be done/written in a shorter [but a little more complex] way. I choose to let it this way to have a "readable" code
		newver=$(cat PKGBUILD | grep pkgver=) && newver=${newver##pkgver=};
		installedver=$(pacman -Q | grep $package) && installedver=${installedver##$package} && installedver=${installedver%%-*};

				if [ $newver == $installedver ]
						then  echo "!****! The same version of package $package is already  installed,skipping...."
						
				fi
			fi
	else (echo "---------- START Making ->  $package -------------------" && makepkg -f ) && sudo pacman -U --noconfirm $package-*.pkg.tar.xz
			
	fi

#break if there is some error
  if [ $? -ne 0 ]
  then
    break
  fi


	
echo "-----> Done building & installing $package"
echo " "

cd ..
done
    
    

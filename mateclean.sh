#!/bin/bash          
# Mate clean helper script by Giovanni "Talorno" Ricciardi <kar98k.sniper@gmail.com>
# IT WIPES OUT ALL THE ALREADY BUILT PACKAGES!!!! WARNING!!!
# Usage: ./mateclean.sh       :)

for dir in ./*
do
if [ -d "$dir" ]; then
    (cd $dir)
    if [ -f $dir/*.pkg.tar.xz ]; then
		rm $dir/*.pkg.tar.xz
	fi
fi
done




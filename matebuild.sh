#!/bin/bash          
# Mate build helper script by Giovanni "Talorno" Ricciardi <kar98k.sniper@gmail.com>
# Usage: ./matebuild.sh       :)


set -e
for dir in ./*
do
if [ -d "$dir" ]; then
	(cd $dir)
	if [ -f $dir/*.pkg.tar.xz ]; then 
	echo "$dir already done ^^!"
	else (echo "---------- START ->  $dir -------------------" && cd $dir && makepkg)
	fi
fi
done

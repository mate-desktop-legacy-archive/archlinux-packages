for dir in ./*
do
    (cd $dir && makepkg)
done

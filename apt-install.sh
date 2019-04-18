install_package()
{
    PACKAGE=$1
    apt-get download $PACKAGE
    dpkg-deb -x $PACKAGE*.deb /my/path
}

#install deb into specific directory

APT_ROOTFS=xenial_arm64_rootfs

main()
{
    destrootfs=$1
    package=$2
    [ ! -d $APT_ROOTFS  ] && echo "error" && exit 99
    [ ! -d $destrootfs  ] && echo "error" && exit 99
    [ "$package" = "" ] && echo "error" && exit 99
    rm -rf $APT_ROOTFS/ttroot
    mkdir $APT_ROOTFS/ttroot
    cat >> $APT_ROOTFS/ttroot/bcmd.sh << EOF
cd /ttroot
pwd
XX=\$(apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances --no-pre-depends ${package} | grep "^\w")
echo \$XX
apt-get download \$XX
ls *.deb | xargs -i dpkg-deb -x {} /ttroot/
rm *.deb'
EOF
    chmod +x $APT_ROOTFS/ttroot/bcmd.sh
    
    chroot $APT_ROOTFS /ttroot/bcmd.sh
    cp -av $APT_ROOTFS/ttroot/* $destrootfs/
    
}
main $@

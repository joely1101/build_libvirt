#!/bin/bash

TARGET=arm64
if [ "$1" = "x64" ];then
    TARGET=x64
    shift
fi

CURDIR=$PWD
env_setup()
{
    BS_BUILDDIR=${CURDIR}/build.$TARGET
    BS_ROOTFS=${CURDIR}/rootfs.$TARGET
    BS_BUILD_NAME=buildme
    BS_LOGDIR=${CURDIR}/logs
    BS_SOURCE_CACHE=/tmp/build_package
    [ ! -d $BS_SOURCE_CACHE ] && mkdir $BS_SOURCE_CACHE
    [ ! -d $BS_LOGDIR ] && mkdir $BS_LOGDIR
    PKG_CONFIG_PATH=${BS_ROOTFS}/lib/pkgconfig/
    PKG_CONFIG_LIBDIR=${PKG_CONFIG_PATH}
    if [ "$TARGET" = "arm64" ];then
        TOOLPATH=/usr/local/gcc-linaro-7.3.1-2018.05-i686_aarch64-linux-gnu/bin
	CROSS_COMPILE=aarch64-linux-gnu-
        CROSS_HOST=aarch64-linux-gnu

        ${TOOLPATH}/${CROSS_COMPILE}gcc -v &>/dev/null
        if [ "$?" != "0" ];then
            echo "toolchain not found, you need put toolchain at /usr/local/gcc-linaro-7.3.1-2018.05-i686_aarch64-linux-gnu"
        exit 99
        fi
    
        #check pkg-config
        PKG_CONF=`which pkg-config`
        eval ${PKG_CONF} -h &>/dev/null
        
        [ "$?" != "0" ] && echo "pkg-config not found please install it" && return
        if [ ! -f ${TOOLPATH}/aarch64-linux-gnu-pkg-config ];then
            echo "please do link for pkg-config"
            echo "ln -sf /usr/bin/pkg-config ${TOOLPATH}/${CROSS_COMPILE}pkg-config"
            exit 99
        fi
        
        CONFIGURE_HOST="--host=$CROSS_HOST"
        PATH=$TOOLPATH:$PATH
    
    elif [ "$TARGET" = "x64" ];then
        CROSS_HOST=x86_64-linux-gnu
    else
        echo "unkonw target"
        exit 99
    fi
    CC=${CROSS_COMPILE}gcc
    CXX=${CROSS_COMPILE}g++

    export PATH BS_ROOTFS PKG_CONFIG_PATH PKG_CONFIG_LIBDIR CROSS_HOST CROSS_COMPILE 
    export CC CXX CONFIGURE_HOST

}
env_show()
{
    echo "BS_BUILDDIR=$BS_BUILDDIR"
    echo "BS_ROOTFS=$BS_ROOTFS"
    echo "BS_SOURCE_CACHE=$BS_SOURCE_CACHE"
    echo "CROSS_HOST=$CROSS_HOST"
    echo "CROSS_COMPILE=$CROSS_COMPILE"
    echo "PKG_CONFIG_PATH=$PKG_CONFIG_PATH"
    echo "PKG_CONFIG_LIBDIR=$PKG_CONFIG_LIBDIR"
    echo "CC=$CC"
    echo "CXX=$CXX"
    echo "ALL_PACKAGE=$ALL_PACKAGE"
}
#check env if OK
env_setup
error_out()
{
    echo $@
    exit 99
}
get_source()
{
    local srcfile=$1
    local builddir=$BS_BUILDDIR/$2
    local source_filename=$(basename $srcfile)
    local source_cached=$BS_SOURCE_CACHE/$source_filename
    if test "$(echo ${srcfile} | grep -c 'http[s]*://.*\.tar\.')" -ne 0; then
        get_type=wget
    elif test "$(echo ${srcfile} | grep -c 'ftp://.*')" -ne 0; then
        get_type=wget
    elif test "$(echo ${srcfile} | grep -c '.*://.*\.git')" -ne 0; then
        get_type=git
    elif test "$(echo ${srcfile} | grep -c 'git://.*')" -ne 0; then
        get_type=git
    else
        error_out "unknow source type"
    fi
    
    if [ "$get_type" = "wget" -a ! -f $source_cached ];then
       wget -O $source_cached $srcfile || error_out "get failed"
    elif [ "$get_type" = "git" -a ! -d $source_cached ];then
       git clone $git_clone_opt $srcfile $source_cached || error_out "git clone failed"
    fi
    
    if [ ! -f $source_cached -a ! -d $source_cached ];then
        error_out "$source_cached not found failed"
    fi
    
    [ ! -d $builddir ] && mkdir -p $builddir
    [ ! -d $builddir/source ] && mkdir -p $builddir/source
    cd $builddir/source

    if [ ! -L $builddir/lsource ];then
        if [ "$get_type" = "wget" ]; then
            tar xf $source_cached || error_out "untar $source_cached failed"
        elif [ "$get_type" = "git" -a ! -d $builddir/lsource ]; then
            git clone $source_cached || error_out "git clone $source_cached failed"
        else
            error_out "unknow type!!"
        fi
        cd - &>/dev/null
        DR=$(find $builddir/source/* -maxdepth 0 -type d)
        DD=$(echo $DR | wc -l)
        [ "$DD" != "1" ] && error_out "source directory '$DR' can't process!!"    
        ln -s $DR $builddir/lsource
    fi

    source_path=$builddir/lsource
    builddir_path=$builddir
    echo "$source_path"
    echo "$builddir_path"
}
build_now()
{
    local CFG_PARAM=$1
    local PRE_CFG_PARAM=$2
    if [ "$3" != "" ];then
        CPUS_JOBS="$3"
    else
        CPUS_JOBS=-j1
    fi
    
    [ "$TARGET" = "x64" ] && PRE_CFG_PARAM+=" CFLAGS=-fPIC"

    mkdir -p $builddir_path/$BS_BUILD_NAME
    if [ ! -f $builddir_path/$BS_BUILD_NAME/build.ok ];then
        cd $builddir_path/$BS_BUILD_NAME && eval $PRE_CFG_PARAM $source_path/configure $CONFIGURE_HOST --prefix=$BS_ROOTFS $CFG_PARAM && make $CPUS_JOBS all install && touch build.ok || error_out "build fail"
        cd - &>/dev/null
    else
        echo "$builddir_path already build"
    fi
    #DESTDIR=$BS_ROOTFS
}
build_generic()
{
    get_source "$1" "$2"
    build_now "$3" "$4" "$5"
}
ALL_PACKAGE=
pkg_add()
{
    if [ "$ALL_PACKAGE" != "" ];then
        ALL_PACKAGE+=" $1"
    else
        ALL_PACKAGE+=" $1"
    fi
}
#######################################################################################
# lib start
######################################################################################
######################libffi###################################
BDIR=libffi
build_libffi()
{
    BDIR=$1
    SOURCE=https://github.com/libffi/libffi/archive/v3.3-rc0.tar.gz
    get_source $SOURCE $BDIR
    [ ! -f ${source_path}/configure ] && cd ${source_path} && ./autogen.sh && cd -
    build_now "" ""
}
pkg_add $BDIR

######################pcre###################################
BDIR=pcre
build_pcre()
{
    SOURCE=ftp://ftp.csx.cam.ac.uk/pub/software/programming/pcre/pcre-8.43.tar.gz
    build_generic "$SOURCE" "$1" "--enable-utf --enable-unicode-properties" ""
}
pkg_add $BDIR

######################pcre###################################
BDIR=libnl
build_libnl()
{
    SOURCE=https://www.infradead.org/~tgr/libnl/files/libnl-3.2.0.tar.gz
    get_source "$SOURCE" "$1"
    sed -i 's/| a29k/| a29k | aarch64/g' ${source_path}/config.sub
    build_now "" "" "" 

}
pkg_add $BDIR

######################zlib###################################
BDIR=zlib
build_zlib()
{
    local SOURCE=https://www.zlib.net/zlib-1.2.11.tar.xz
    get_source "$SOURCE" "$1"
    
    mkdir -p $builddir_path/$BS_BUILD_NAME
    if [ ! -f $builddir_path/$BS_BUILD_NAME/build.ok ];then
        cd $builddir_path/$BS_BUILD_NAME && \
        CC=${CROSS_COMPILE}gcc  AR=${CROSS_COMPILE}ar $source_path/configure --prefix=$BS_ROOTFS && make all install && touch build.ok || error_out "build fail"
        cd - &>/dev/null
    else
        echo "$builddir_path already build"
    fi
}
pkg_add $BDIR

######################glib###################################

BDIR=glib
build_glib()
{
    local SOURCE=https://download.gnome.org/sources/glib/2.49/glib-2.49.7.tar.xz
    local CFG_PRE="ac_cv_type_long_long=yes glib_cv_stack_grows=no glib_cv_uscore=no ac_cv_func_posix_getpwuid_r=yes ac_cv_func_posix_getgrgid_r=yes glib_cv_pcre_has_unicode=yes"
    local CFG_PARAM="--without-libiconv"
    build_generic "$SOURCE" "$1" "$CFG_PARAM" "$CFG_PRE" "-j1"
    
    #work arround....
    echo workarround ....
    sed -i 's/Libs: -L${libdir} -lglib-2.0/Libs: -L${libdir} -lpcre -lglib-2.0/g' $PKG_CONFIG_PATH/glib-2.0.pc
    cd - &>/dev/null
    
}
pkg_add $BDIR
######################nettle###################################
BDIR=nettle
build_nettle()
{
    local SOURCE=https://ftp.gnu.org/gnu/nettle/nettle-3.4.1.tar.gz
    local CFG_PARAM="--enable-gmp --enable-shared --enable-mini-gmp"
    build_generic "$SOURCE" "$1" "$CFG_PARAM" "" "-j1"
}
pkg_add $BDIR

######################pixman###################################
BDIR=pixman
build_pixman()
{
    local SOURCE=https://www.cairographics.org/releases/pixman-0.38.0.tar.gz
    build_generic "$SOURCE" "$1" "" ""
}
pkg_add $BDIR


######################gmp###################################
BDIR=gmp
build_gmp()
{
    local SOURCE=https://gmplib.org/download/gmp/gmp-6.1.2.tar.xz
    local CFG_PARAM=
    #gmp not support make -jx
    build_generic "$SOURCE" "$1" "$CFG_PARAM" "" "-j1"
}
pkg_add $BDIR

################################################################
BDIR=libxml2
build_libxml2()
{
    local SOURCE=ftp://xmlsoft.org/libxml2/libxml2-sources-2.9.9.tar.gz
    local CFG_PARAM="--without-python"
    build_generic "$SOURCE" "$1" "$CFG_PARAM" ""
}
pkg_add $BDIR

################################################################
BDIR=cyrus-sasl
build_cyrus-sasl()
{
    local SOURCE=https://github.com/cyrusimap/cyrus-sasl/releases/download/cyrus-sasl-2.1.27/cyrus-sasl-2.1.27.tar.gz
    local CFG_PARAM=""
    build_generic "$SOURCE" "$1" "$CFG_PARAM" ""
}
#pkg_add $BDIR
################################################################
BDIR=aio
build_aio()
{
    local SOURCE=http://ftp.de.debian.org/debian/pool/main/liba/libaio/libaio_0.3.112.orig.tar.xz
    get_source $SOURCE $1
    make -C ${source_path} all install DESTDIR=$BS_ROOTFS
}
#pkg_add $BDIR

################################################################
BDIR=lvm2
build_lvm2()
{
    local SOURCE=ftp://sources.redhat.com/pub/lvm2/LVM2.2.03.02.tgz
    local CFG_PARAM="CFLAGS='-I$BS_ROOTFS/include/ -I$BS_ROOTFS/usr/include' LDFLAGS='-L$BS_ROOTFS/lib/ -L$BS_ROOTFS/usr/lib/ -L$BS_ROOTFS/lib64/'"
    local CFG_PRE="ac_cv_func_realloc_0_nonnull=yes ac_cv_func_malloc_0_nonnull=yes"
    get_source $SOURCE $1
    
    mkdir -p $builddir_path/$BS_BUILD_NAME
    if [ ! -f $builddir_path/$BS_BUILD_NAME/build.ok ];then
        cd $builddir_path/$BS_BUILD_NAME && eval $CFG_PRE $source_path/configure $CONFIGURE_HOST --prefix=$BS_ROOTFS $CFG_PARAM && make $CPUS_JOBS all install DESTDIR=$BS_ROOTFS && touch build.ok || error_out "build fail"
        cd - &>/dev/null
    else
        echo "$builddir_path already build"
    fi
    
    #build_generic "$SOURCE" "$1" "$CFG_PARAM" "$CFG_PRE"
}
#pkg_add $BDIR
######################gnutls###################################
BDIR=yajl
build_yajl()
{
    local SOURCE=https://github.com/lloyd/yajl/archive/1.0.12.tar.gz
    local CFG_PRE=
    local CFG_PARAM=
    get_source $SOURCE $1
    cd ${source_path} && CC=$CC CFLAGS=-fPIC ./configure --prefix=$BS_ROOTFS || error_out "configure failed"
    cd -
    cd ${source_path}/build && make all install || error_out "build failed"
    cd -
}
pkg_add $BDIR


######################gnutls###################################
BDIR=gnutls
build_gnutls()
{
    local SOURCE=https://www.gnupg.org/ftp/gcrypt/gnutls/v3.6/gnutls-3.6.0.tar.xz
    local CFG_PRE="GMP_LIBS='-L$BS_ROOTFS/lib/ -lgmp' "
    local CFG_PARAM="GMP_LIBS='-L$BS_ROOTFS/lib/ -lgmp' --with-included-libtasn1 --with-included-unistring "
    CFG_PARAM+="--without-p11-kit "
    #CFG_PARAM+="--with-default-trust-store-pkcs11='pkcs11:' "
    build_generic "$SOURCE" "$1" "$CFG_PARAM" "$CFG_PRE"
}
pkg_add $BDIR
#################################################################
BDIR=qemu

build_qemu()
{
    local PARAM=""
    PARAM+="--enable-attr "
    PARAM+="--enable-kvm "
    #disable almost feature ....    
    PARAM+="--disable-bsd-user "
    PARAM+="--disable-strip "
    PARAM+="--disable-werror "
    PARAM+="--disable-gcrypt "
    PARAM+="--enable-debug-info "
    PARAM+="--enable-debug "
    PARAM+="--disable-debug-tcg "
    PARAM+="--disable-docs "
    PARAM+="--disable-tcg-interpreter "
    PARAM+="--disable-brlapi "
    PARAM+="--disable-linux-aio "
    PARAM+="--disable-bzip2 "
    PARAM+="--disable-bluez "
    PARAM+="--disable-cap-ng "
    PARAM+="--disable-curl "
    PARAM+="--disable-glusterfs "
    PARAM+="--disable-gnutls "
    #PARAM+="--disable-nettle "
    PARAM+="--disable-gtk "
    PARAM+="--disable-rdma "
    PARAM+="--disable-libiscsi "
    PARAM+="--disable-vnc-jpeg "
    PARAM+="--disable-lzo "
    PARAM+="--disable-curses "
    PARAM+="--disable-libnfs "
    PARAM+="--disable-numa "
    PARAM+="--disable-opengl "
    PARAM+="--disable-vnc-png "
    PARAM+="--disable-rbd "
    PARAM+="--disable-vnc-sasl "
    PARAM+="--disable-sdl "
    PARAM+="--disable-seccomp "
    PARAM+="--disable-smartcard "
    PARAM+="--disable-snappy "
    PARAM+="--disable-spice "
    PARAM+="--disable-libssh2 "
    PARAM+="--disable-libusb "
    PARAM+="--disable-usb-redir "
    PARAM+="--disable-vde "
    #PARAM+="--disable-vhost-net "
    PARAM+="--disable-virglrenderer "
    PARAM+="--disable-virtfs "
    PARAM+="--disable-vnc "
    PARAM+="--disable-vte "
    PARAM+="--disable-xen "
    PARAM+="--disable-xen-pci-passthrough "
    PARAM+="--disable-xfsctl "
    #PARAM+="--disable-blobs "
    PARAM+="--disable-tools "
    PARAM+="--disable-pie "
    #PARAM+="--extra-ldflags='-L$BS_ROOTFS/lib/ -L$BS_ROOTFS/usr/lib/ -L$BS_ROOTFS/lib64/ -lgmp -lhogweed'"
    PRE_CFG=
    if [ "$TARGET" = "arm64" ];then
        QEMU_TGT=aarch64-softmmu
    elif [ "$TARGET" = "x64" ];then
        QEMU_TGT=x86_64-softmmu
    fi
    local CFG_PARAM="--cross-prefix=${CROSS_COMPILE}  --target-list='$QEMU_TGT' $PARAM"
    
    local SOURCE=https://download.qemu.org/qemu-3.1.0.tar.xz    
    
    get_source $SOURCE $1
    build_generic "$SOURCE" "$1" "$CFG_PARAM" "$PRE_CFG" "-j1"
}
pkg_add $BDIR

################################################################
BDIR=libvirt
build_libvirt()
{
    local SOURCE=https://libvirt.org/sources/libvirt-5.0.0.tar.xz
    #local CFG_PARAM="--with-macvtap --without-xenapi --with-storage-fs --without-storage-mpath --with-yajl=$BS_ROOTFS --with-xml2=$BS_ROOTFS"
#    local CFG_PARAM="--with-macvtap=yes --without-esx --without-xenapi --without-xen --without-lxc --with-storage-fs --without-storage-mpath --with-yajl=$BS_ROOTFS --with-xml2=$BS_ROOTFS --without-udev"
    local CFG_PARAM="--with-macvtap --without-numactl --without-dbus --without-firewalld --without-fuse --without-pm-utils  --without-esx --without-lxc --without-storage-mpath --with-yajl=$BS_ROOTFS --with-xml2=$BS_ROOTFS"
    local CFG_PRE=""
    CFG_PARAM+=" --without-libxl --with-xen-inotify --without-xenapi --without-xen"    
    CFG_PARAM+=" --without-selinux --without-selinux-mount"
    CFG_PARAM+=" -without-hyperv --without-esx --with-virtualport --without-xdr --without-sasl"
    CFG_PARAM+=" --without-uml --without-openvz --without-vmware --without-vbox"
    CFG_PARAM+=" --without-storage-lvm --without-storage-fs --without-storage-netfs --without-storage-fs --without-storage-zfs --without-glusterfs --without-storage-iscsi --without-storage-scsi"
    #--with-macvtap=yes
    get_source "$SOURCE" "$1"
    mkdir -p $builddir_path/$BS_BUILD_NAME
    if [ ! -f $builddir_path/$BS_BUILD_NAME/build.ok ];then
        cd $builddir_path/$BS_BUILD_NAME
        if [ ! -f $builddir_path/$BS_BUILD_NAME/Makefile ];then
            eval $PRE_CFG_PARAM $source_path/configure $CONFIGURE_HOST --prefix=/usr $CFG_PARAM
            #rework config.h
            #sed -i "s/HAVE_DECL_DEVLINK_CMD_ESWITCH_GET 1/HAVE_DECL_DEVLINK_CMD_ESWITCH_GET 0/g" $builddir_path/$BS_BUILD_NAME/config.h
        fi 
        make -j4  V=1 $CPUS_JOBS all install DESTDIR=$BS_ROOTFS && touch build.ok || error_out "build fail"
        cd - &>/dev/null
    else
        echo "$builddir_path already build"
    fi
    
    #build_generic "$SOURCE" "$1" "$CFG_PARAM" "$CFG_PRE"
}
pkg_add $BDIR

build_busybox()
{
    local SOURCE=https://www.busybox.net/downloads/busybox-1.30.1.tar.bz2
    local CFG_PARAM=""
    local CFG_PRE=""
    get_source $SOURCE $1
    if [ ! -f ${source_path}/.config ];then
        make -C ${source_path}/ defconfig
        sed -i "s/CONFIG_CROSS_COMPILER_PREFIX=\"\".*/CONFIG_CROSS_COMPILER_PREFIX=\"$CROSS_COMPILE\"/g" ${source_path}/.config
        sed -i "s/# CONFIG_STATIC is not set/CONFIG_STATIC=y/g" ${source_path}/.config
    fi
    make -C ${source_path}/ clean all install CONFIG_PREFIX=$BS_ROOTFS || error_out "build fail"
}    
pkg_add busybox
prepare_file()
{
    cat > $BS_ROOTFS/run.sh << EOF	    
#!/bin/sh
#need mount ..
mkdir -p dev proc sys
mount -o bind /dev/ dev
mount -o bind /dev/pts dev/pts
mount -o bind /proc/ proc
./bin/busybox chroot . /bin/ash
umount proc dev/pts dev sys
EOF
    if [ "$TARGET" = "arm64" ];then
        QEMU_NAME=qemu-system-aarch64
    elif [ "$TARGET" = "x64" ];then
        QEMU_NAME=qemu-system-x86_64
    else
        echo "unknow type"
    fi
    
    cat > $BS_ROOTFS/usr/bin/kvm << EOF	    
#!/bin/sh
exec $QEMU_NAME -enable-kvm "\$@"
EOF

}
strip_files()
{
    STRIP=${CROSS_COMPILE}strip
    find $BS_ROOTFS -name *.a | xargs rm -f
    find $BS_ROOTFS -name *.la | xargs rm -f
    #find $BS_ROOTFS -type f -name *.so* | xargs $STRIP
    find $BS_ROOTFS -executable -type f | xargs $STRIP
    #remove grabage....
    mv $BS_ROOTFS/share/qemu $BS_ROOTFS/
    rm -rf $BS_ROOTFS/share/*
    mv $BS_ROOTFS/qemu $BS_ROOTFS/share/
    
    mv $BS_ROOTFS/usr/share/libvirt $BS_ROOTFS/
    rm -rf $BS_ROOTFS/usr/share/*
    mv $BS_ROOTFS/libvirt $BS_ROOTFS/usr/share/
}

build_toolslib_arm64()
{
    #copy rootfs/lib/ xxx to rootfs.release
    #copy toolchain lob to rootfs.release
    cp -a /usr/local/gcc-linaro-7.3.1-2018.05-i686_aarch64-linux-gnu/aarch64-linux-gnu/lib64/*.so $BS_ROOTFS/lib/
    cp -a /usr/local/gcc-linaro-7.3.1-2018.05-i686_aarch64-linux-gnu/aarch64-linux-gnu/lib64/*.so.* $BS_ROOTFS/lib/
    cp -a /usr/local/gcc-linaro-7.3.1-2018.05-i686_aarch64-linux-gnu/aarch64-linux-gnu/libc/lib/*.so $BS_ROOTFS/lib/
    cp -a /usr/local/gcc-linaro-7.3.1-2018.05-i686_aarch64-linux-gnu/aarch64-linux-gnu/libc/lib/*.so.* $BS_ROOTFS/lib/
    ln -sf /lib/ld-2.25.so $BS_ROOTFS/lib/ld-linux-aarch64.so.1  
    prepare_file
}
if [ "$TARGET" = "arm64" ];then
pkg_add toolslib_arm64
fi

build_toolslib_x86()
{
    prepare_file
    #download libc6
    libcdeb=`ls libc6*.deb`
    echo "$libcdeb"
    [ "$libcdeb" = "" ] && apt-get download libc6
    libcdeb=`ls libc6*.deb`
    [ "$libcdeb" = "" ] && echo "libc not found" && return
    dpkg-deb -x $libcdeb $BS_ROOTFS
    
    cp /lib/x86_64-linux-gnu/libgcc_s.so.1 $BS_ROOTFS/lib/x86_64-linux-gnu/libgcc_s.so.1
    cp /etc/passwd /etc/group $BS_ROOTFS/etc/
    strip_files
}
if [ "$TARGET" = "x64" ];then
pkg_add toolslib_x86
fi

#################################################################
clean_list()
{
    package=$1
    if [ "$package" = "all" ];then
        BUILD_PACKAGE=$ALL_PACKAGE
        echo "remove rootfs"
        rm -rf $BS_ROOTFS
        rm -f $BS_LOGDIR/*
    else
        BUILD_PACKAGE=$package
    fi
    
    for pp in $BUILD_PACKAGE
    do
        echo "remove $pp ..."
        rm -rf $BS_BUILDDIR/$pp
    done
}
build_list()
{
    package=$1
    if [ "$package" != "" -a "$package" != "all" ];then
        found=0
        for pp in $ALL_PACKAGE
        do
            if [ "$pp" = "$package" ];then
                found=1
                break
            fi
        done
        
        if [ $found -eq 1 ]; then
            echo "$package found"
        else
            echo "warning ....$package maybe not support"
            cd $CURDIR
            exit 99
        fi
        BUILD_PACKAGE=$package
    else
        BUILD_PACKAGE=$ALL_PACKAGE    
    fi
    
    for pp in $BUILD_PACKAGE
    do
        echo "run build_${pp}"
        cd $BS_BUILDDIR
        eval build_${pp} "$pp"
        if [ "$?" = "0" ];then
            echo "build $pp success...." 
        else
            echo "build $pp error...."
            break
        fi
    done

}

main()
{

    [ ! -d $BS_BUILDDIR ] && mkdir $BS_BUILDDIR
    [ ! -d $BS_ROOTFS ] && mkdir $BS_ROOTFS
    case $1 in
    show) 
        env_show
        ;;
    build) 
        shift
        build_list $@
        ;;
    clean) 
        shift
        clean_list $@
        ;;
    pall) 
        PL1="libffi pcre zlib glib nettle pixman gmp libxml2 cyrus-sasl aio "
        PL2="lvm2 gnutls "
        PL3="qemu libvirt "
        echo "$PL1" | xargs -d ' ' -P 4 -i sh -c './bvirt.sh build {}'
        echo "$PL2" | xargs -d ' ' -P 2 -i sh -c './bvirt.sh build {}'
        echo "$PL3" | xargs -d ' ' -P 2 -i sh -c './bvirt.sh build {}'
        ;;
    rootfs)
        #copy rootfs/lib/ xxx to rootfs.release
        #copy toolchain lob to rootfs.release
        cp -a /usr/local/gcc-linaro-7.3.1-2018.05-i686_aarch64-linux-gnu/aarch64-linux-gnu/lib64/*.so ./rootfs/lib/
        cp -a /usr/local/gcc-linaro-7.3.1-2018.05-i686_aarch64-linux-gnu/aarch64-linux-gnu/lib64/*.so.* ./rootfs/lib/
        cp -a /usr/local/gcc-linaro-7.3.1-2018.05-i686_aarch64-linux-gnu/aarch64-linux-gnu/libc/lib/*.so ./rootfs/lib/
	    cp -a /usr/local/gcc-linaro-7.3.1-2018.05-i686_aarch64-linux-gnu/aarch64-linux-gnu/libc/lib/*.so.* ./rootfs/lib/
	    ln -sf /lib/ld-2.25.so ./rootfs/lib/ld-linux-aarch64.so.1  
        ;;
    *)
        echo "usage"
        echo "$0 show - show environment and packages"
        echo "$0 build [ pkg_name | all ] - downlnaod and compile"
        ;;
    esac
}
exec &> >(tee $BS_LOGDIR/build.log)
#check env if OK
env_setup

main $@
cd ${CURDIR}


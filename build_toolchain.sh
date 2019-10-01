#!/bin/bash
# Original script stolen from: https://www.held-im-ruhestand.de/software/embedded/cross-compiler.html 
set -e
set -u

# This directory is used as root for all operations
BASE=$(dirname "$0")
BASE=$(cd "$BASE" && pwd)

TARGET=arm-unknown-linux-gnueabi
BUILD=$(gcc -dumpmachine)
ARCH=arm

SYSROOT="$BASE/sysroot"     # files for the target system 
TOOLCHAIN="$BASE/toolchain" # the cross compilers
SRCDIR="$BASE/src"          # saving tarballs
WORKDIR="$BASE/work"        # unpacked tarballs
BUILDDIR="$BASE/build"      # running compile 
LOGDIR="$BASE/logs"         # various logs
PARALLEL="-j$(nproc)"       # use all of the cores we got

# Software Versions to use
BINUTILS=binutils-2.20.1
KERNEL=linux-2.6.32.9
GCC=gcc-4.5.1
GMP=gmp-4.3.1
MPC=mpc-0.8.1
MPFR=mpfr-2.4.2
GLIBC=glibc-2.11.1
GLIBCPORTS=glibc-ports-2.11

GREEN="\e[38;5;118m"
RED="\e[38;5;203m"
GREY="\e[38;5;245m"
YELLOW="\e[38;5;208m"
END="\e[0m"
 
GOOD="[$GREEN+$END]"
BAD="[$RED-$END]"
STAT="[$GREY*$END]"
WARN="[$YELLOW!$END]"


success_message(){
    echo -e "$GREEN"
    echo " ___                    "
    echo "|   \  ___  _ __   ___  "
    echo "| |\ |/ _ \| '_ \ / _ \ "
    echo "| |/ | (_) | | | |  __/ "
    echo "|___/ \___/|_| |_|\___| "
    echo "                        "
    echo -e "$END"
    exit 1
}

failed_message(){
    echo -e "$RED"
    echo " _____       _  _           _ "
    echo "| ____| ___ |_|| | ___   __| |"
    echo "| |_   / _ \ _ | |/ _ \ / _  |"
    echo "| __| ( (_) | || |  __/( (_| |"
    echo "|_|    \__|_|_||_|\___| \__,_|"
    echo "                              "
    echo -e "$END"
    exit 1
}

# Reconfigures the default shell to bash, instead of dash.
set_default_shell(){
    MYSH=$(readlink -f /bin/sh)
    if [ "$MYSH" == "/usr/bin/dash" ]; then
        do_msg "Setup" "/bin/sh set to /usr/bin/dash; needs to be /usr/bin/bash. Press $GREEN-Return-$END to reconfigure." "WARN"
        read doesntmatter
        echo "sudo dpkg-reconfigure dash" >> $COMMAND_LOG
        sudo dpkg-reconfigure dash
        MYSH=$(readlink -f /bin/sh)
        if [ "$MYSH" == "/usr/bin/dash" ]; then
            do_msg "Setup" $RED"Error$END: Failed to set default shell to bash. Exiting." "BAD"
            exit 1
        else
            do_msg "Setup" "Successfully set default shell to bash." "GOOD"
        fi
    fi
}

# Checks if the supplied package is installed. If not, attempts to install the package.
# If it fails to find the package after trying to install the package, displays error and exits.
install_missing_package() {
    PACKAGE_NAME=$1
    PACKAGE_INSTALLED=$(dpkg-query -W --showformat='${Status}\n' $PACKAGE_NAME | grep "install ok installed")
    echo -e -n "$STAT Checking for $PACKAGE_NAME..."
    if [ "" == "$PACKAGE_INSTALLED" ]; then
        echo -e " $RED""not found!!$END"
        echo -e "$WARN $YELLOW""Installing $PACKAGE_NAME...$END"
        APT_INSTALL=$(sudo apt-get --yes install $PACKAGE_NAME)
        echo "sudo apt-get --yes install $PACKAGE_NAME" >> $COMMAND_LOG
        PACKAGE_INSTALLED=$(dpkg-query -W --showformat='${Status}\n' $PACKAGE_NAME | grep "install ok installed")
        if [ "" == "$PACKAGE_INSTALLED" ]; then
            echo -e "$BAD$RED""FAILED TO INSTALL REQUIRED PACKAGE!! ABORT!!"
            exit 1
        fi
    else
        PACKAGE_VERSION=$(dpkg-query -W --showformat='${Version}' $PACKAGE_NAME)
        echo -e " $GREEN$PACKAGE_NAME=$PACKAGE_VERSION$END"
    fi
}

# Makes directories for the supplied path, including parents, and logs the oepration to the command log. 
make_dir() {
    dir_path=$1
    if [ ! -d "$dir_path" ]; then
        echo "mkdir -p $dir_path" >> $COMMAND_LOG
        mkdir -p $dir_path
    fi
}

# Apply a supplied patch to the supplied file, and logs the operation to the command log.
do_patch(){
    target=$1
    patch_path=$2
    echo "patch -f $target $patch_path" >> $COMMAND_LOG
    if ( patch -f $target $patch_path ) ; then
        echo -e "$GOOD Successfully applied patch: $target -> $patch_path""$END"
    else
        echo -e "$WARN Failed to apply patch: $target -> $patch_path""$END"
    fi
}

# Downloads the resource at the supplied URL into the SRCDIR.
get_url() {
	url=$1
	file=${url##*/}
	if [ ! -f "$SRCDIR/$file" ]; then
		echo "downloading $file from $url"
		echo "wget \"$url\" -O \"$BASE/src/$file\"" >> $COMMAND_LOG
		wget "$url" -O "$BASE/src/$file"
	fi
}

# Extracts b/g zipped files into the cwd or a supplied destination, and renames the dir, if new name is supplied.
# Does nothing if the zip's extracted target already exists inside of the destination dir. 
# Destination defaults to WORKDIR. 
unpack() {
	file=$1
	destination=${2:-$WORKDIR}
	new_name=${3:-""}
	ext=${file##*.}
	folder=${file%%.tar.*}

    if [ "$new_name" != "" ]; then
        if [ -d "$destination/$new_name" ]; then
    		return 0
    	fi
    fi

    # if untar'd dir already exists, don't untar again.
	if [ -d "$destination/$folder" ]; then
		return 0
	else
		echo -e "$STAT unpacking $file to $WORKDIR..."
	fi
	tar_args="zxf"
	if [ "$ext" == "bz2" ]; then
	    tar_args="jxf"
    fi
    echo "tar $tar_args $SRCDIR/$file -C $destination" >> $COMMAND_LOG
    tar $tar_args $SRCDIR/$file -C $destination
    
    if [ "$new_name" != "" ]; then
        echo "mv -v $destination/$folder $destination/$new_name" >> $COMMAND_LOG
        mv -v $destination/$folder $destination/$new_name
    fi
}

# Originally function that checks if we're done by looking for touched files.
# TODO: make this overall idea better.
check_done() {
	OBJ=$1
	if [ -f $BUILDDIR/$OBJ.done ]; then
		echo "already done"
		return 0
	fi
	return 1
}

# Original function that
do_msg() {
	OBJECT=$1
	ACTION=$2
	STATUS=${3:-"STAT"}
	echo "# $OBJECT - $ACTION" >> $COMMAND_LOG
	case $STATUS in
        GOOD)
            echo -e "$GOOD $OBJECT - $ACTION"
        ;;
        BAD)
            echo -e "$BAD $OBJECT - $ACTION"
        ;;
        WARN)
            echo -e "$WARN $OBJECT - $ACTION"
        ;;
        *)
            echo -e "$STAT $OBJECT - $ACTION"
        ;;
    esac	
}

binutils() {
	OBJ=$BINUTILS
	do_msg $OBJ "start configure"
	check_done $OBJ && return 0
	echo "mkdir -p $BUILDDIR/$OBJ" >> $COMMAND_LOG
	mkdir -p $BUILDDIR/$OBJ
	pushd $BUILDDIR/$OBJ
	if [ ! -f Makefile ]; then
	    echo "$WORKDIR/$OBJ/configure --target=$TARGET --prefix=$TOOLCHAIN --with-sysroot=$SYSROOT --disable-nls --disable-werror" >> $COMMAND_LOG
		$WORKDIR/$OBJ/configure \
			--target=$TARGET \
			--prefix=$TOOLCHAIN \
			--with-sysroot=$SYSROOT \
			--disable-nls \
			--disable-werror
	fi
	do_msg $OBJ "do     make"
	echo "make $PARALLEL 2>&1 | tee $LOGDIR/$OBJ""_make.log" >> $COMMAND_LOG
	make $PARALLEL 2>&1 | tee "$LOGDIR/$OBJ""_make.log"
	do_msg $OBJ "do make install to $TOOLCHAIN/$TARGET"
	echo "make all install 2>&1 | tee $LOGDIR/$OBJ""_make_all_install.log" >> $COMMAND_LOG
	make all install 2>&1 | tee "$LOGDIR/$OBJ""_make_all_install.log" 
	do_msg $OBJ "done"
	echo "touch $BUILDDIR/$OBJ.done" >> $COMMAND_LOG
	touch $BUILDDIR/$OBJ.done
	popd
}

gccstatic() {
	# static gcc, only C, able to compile the libc
	# would be enough if we only compile kernels
	OBJ=$GCC-static
	do_msg $OBJ "start configure"
	check_done $OBJ && return 0
	echo "mkdir -p $BUILDDIR/$OBJ" >> $COMMAND_LOG
	mkdir -p $BUILDDIR/$OBJ
	pushd $BUILDDIR/$OBJ
	if [ ! -f Makefile ]; then
	    echo "$WORKDIR/$GCC/configure --target=$TARGET --prefix=$TOOLCHAIN --with-gmp-includes=$BUILDDIR/$OBJ/gmp --with-gmp-lib=$BUILDDIR/$OBJ/gmp/.libs --without-headers --with-newlib --disable-shared --disable-threads --disable-libssp --disable-libgomp --disable-libmudflap --disable-nls --disable-multilib --disable-decimal-float --enable-languages=c --without-ppl --without-cloog" >> $COMMAND_LOG
		$WORKDIR/$GCC/configure \
			--target=$TARGET \
			--prefix=$TOOLCHAIN \
			--with-gmp-include=$BUILDDIR/$OBJ/gmp \
			--with-gmp-lib=$BUILDDIR/$OBJ/gmp/.libs \
			--without-headers \
			--with-newlib \
			--disable-shared \
			--disable-threads \
			--disable-libssp \
			--disable-libgomp \
			--disable-libmudflap \
			--disable-nls \
			--disable-multilib \
			--disable-decimal-float \
			--enable-languages=c \
			--without-ppl \
			--without-cloog 2>&1 | tee "$LOGDIR/$OBJ""_static_configure.log"
	fi
	do_msg $OBJ "do make"
	echo "PATH=$TOOLCHAIN/bin:$PATH make $PARALLEL 2>&1 | tee $LOGDIR/$OBJ""_make.log" >> $COMMAND_LOG
	PATH=$TOOLCHAIN/bin:$PATH \
	make $PARALLEL 2>&1 | tee "$LOGDIR/$OBJ""_static_make.log"
	do_msg $OBJ "do make install to $TOOLCHAIN/$TARGET"
	echo "PATH=$TOOLCHAIN/bin:$PATH make install 2>&1 | tee $LOGDIR/$OBJ""_make_install.log" >> $COMMAND_LOG
	PATH=$TOOLCHAIN/bin:$PATH \
	make install 2>&1 | tee "$LOGDIR/$OBJ""_make_static_install.log"

    if [ -f $TOOLCHAIN/lib/gcc/$TARGET/$(echo $GCC | cut -d "-" -f2)/libgcc.a ]; then
        if [ ! -f `/$TOOLCHAIN/bin/$TARGET-gcc -print-libgcc-file-name | sed 's/libgcc/&_eh/'` ]; then
            ln -vs $TOOLCHAIN/lib/gcc/$TARGET/$(echo $GCC | cut -d "-" -f2)/libgcc.a `/$TOOLCHAIN/bin/$TARGET-gcc -print-libgcc-file-name | sed 's/libgcc/&_eh/'`
        fi
        do_msg $OBJ "Successfully compiled"
    	echo "touch $BUILDDIR/$OBJ.done" >> $COMMAND_LOG
    	touch $BUILDDIR/$OBJ.done
    else
        do_msg $OBJ "Failed to compile" "BAD"
        echo -e "$BAD$RED Grep'd errors from log files:$END\n"
        grep "Error" "$LOGDIR/$OBJ""_make.log"
        grep "Error" "$LOGDIR/$OBJ""_make_install.log"
        echo "\n"
        failed_message
    fi
	popd
}

gccminimal() {
	OBJ=$GCC-min
	do_msg $OBJ "start"
	check_done $OBJ && return 0
	mkdir -p $BUILDDIR/$OBJ
	pushd $BUILDDIR/$OBJ
	if [ ! -f Makefile ]; then
		$WORKDIR/$GCC/configure \
			--target=$TARGET \
			--prefix=$TOOLCHAIN \
			--with-sysroot=$SYSROOT \
			--disable-libssp \
			--disable-libgomp \
			--disable-libmudflap \
			--disable-shared \
			--disable-nls \
			--enable-languages=c 2>&1 | tee "$LOGDIR/$OBJ""_minimal_configure.log"
	fi
	do_msg $OBJ "compile"
	PATH=$TOOLCHAIN/bin:$PATH \
	make $PARALLEL 2>&1 | tee "$LOGDIR/$OBJ""_minimal_make.log"
	do_msg $OBJ "install"
	PATH=$TOOLCHAIN/bin:$PATH \
	make install 2>&1 | tee "$LOGDIR/$OBJ""_minimal_make_install.log" 
	do_msg $OBJ "done"
	touch $BUILDDIR/$OBJ.done
	popd
}

gccfull() {
	OBJ=$GCC
	do_msg $OBJ "start"
	check_done $OBJ && return 0
	mkdir -p $BUILDDIR/$OBJ
	pushd $BUILDDIR/$OBJ
	if [ ! -f Makefile ]; then
		$WORKDIR/$GCC/configure \
			--target=$TARGET \
			--prefix=$TOOLCHAIN \
			--with-sysroot=$SYSROOT \
			--enable-__cxy_atexit \
			--disable-libssp \
			--disable-libgomp \
			--disable-libmudflap \
			--enable-languages=c,c++ \
			--disable-nls 2>&1 | tee "$LOGDIR/$OBJ""_full_configure.log"
	fi
	do_msg $OBJ "compile"
	PATH=$TOOLCHAIN/bin:$PATH \
	make $PARALLEL 2>&1 | tee "$LOGDIR/$OBJ""_full_make.log"
	do_msg $OBJ "install"
	PATH=$TOOLCHAIN/bin:$PATH \
	make install 2>&1 | tee "$LOGDIR/$OBJ""_full_make_install.log" 
	do_msg $OBJ "done"
	touch $BUILDDIR/$OBJ.done
	popd
}

kernelheader() { 
	OBJ=$KERNEL
	check_done $OBJ && return 0
	pushd $WORKDI   R/$OBJ
	do_msg $OBJ "Starting Linux header make"
	echo "make mrproper" >> $COMMAND_LOG
	make mrproper 2>&1 | tee "$LOGDIR/$OBJ""_make.log"
	make headers_check 2>&1 | tee "$LOGDIR/$OBJ""_make_headers_check.log"
	do_msg $OBJ "Installing toolchain headers"
	echo "PATH=$TOOLCHAIN/bin:$PATH make ARCH=$ARCH INSTALL_HDR_PATH=$SYSROOT/usr CROSS_COMPILE=$TARGET- headers_install" >> $COMMAND_LOG
	PATH=$TOOLCHAIN/bin:$PATH \
	make \
		ARCH=$ARCH \
		INSTALL_HDR_PATH=$SYSROOT/usr \
		CROSS_COMPILE=$TARGET- \
		headers_install 2>&1 | tee "$LOGDIR/$OBJ""_make_install-headers.log"
	cp -r $SYSROOT/usr/* $TOOLCHAIN/
	do_msg $OBJ "done"
	echo "touch $BUILDDIR/$OBJ.done" >> $COMMAND_LOG
	touch $BUILDDIR/$OBJ.done
	popd
}

glibcheader() {
	OBJ=$GLIBC-header
	do_msg $OBJ "start"
	check_done $OBJ && return 0
	mkdir -p $BUILDDIR/$OBJ
	pushd $BUILDDIR/$OBJ
	if [ ! -f Makefile ]; then
	
	echo "BUILD_CC=gcc CC=$TOOLCHAIN/bin/$TARGET-gcc CXX=$TOOLCHAIN/bin/$TARGET-g++ AR=$TOOLCHAIN/bin/$TARGET-ar LD=$TOOLCHAIN/bin/$TARGET-ld RANLIB=$TOOLCHAIN/bin/$TARGET-ranlib $WORKDIR/$GLIBC/configure --prefix=/usr --with-headers=$SYSROOT/usr/include --build=$BUILD --host=$TARGET --disable-nls --disable-profile --without-gd --without-cvs --enable-add-ons=nptl,ports libc_cv_forced_unwind=yes libc_cv_c_cleanup=yes" >> $COMMAND_LOG
	
		BUILD_CC=gcc \
		CC=$TOOLCHAIN/bin/$TARGET-gcc \
		CXX=$TOOLCHAIN/bin/$TARGET-g++ \
		AR=$TOOLCHAIN/bin/$TARGET-ar \
		LD=$TOOLCHAIN/bin/$TARGET-ld \
		RANLIB=$TOOLCHAIN/bin/$TARGET-ranlib \
		$WORKDIR/$GLIBC/configure \
			--prefix=/usr \
			--with-headers=$SYSROOT/usr/include \
			--build=$BUILD \
			--host=$TARGET \
			--disable-nls \
			--disable-profile \
			--without-gd \
			--without-cvs \
			--enable-shared \
			--enable-add-ons=nptl,ports \
			libc_cv_forced_unwind=yes \
            libc_cv_c_cleanup=yes 2>&1 | tee "$LOGDIR/$OBJ""_configure.log"
	fi
	do_msg $OBJ "install"
	make \
		install-headers \
		install_root=$SYSROOT \
		install-bootstrap-headers=yes 2>&1 | tee "$LOGDIR/$OBJ""_make_install-headers.log"
	do_msg $OBJ "crtX and fake libc"
	make csu/subdir_lib 2>&1 | tee "$LOGDIR/$OBJ""_make_csu_lib.log"
	mkdir -p $SYSROOT/usr/lib
	cp csu/crt1.o csu/crti.o csu/crtn.o $SYSROOT/usr/lib
	# build a dummy libc
	$TOOLCHAIN/bin/$TARGET-gcc \
		-nostdlib \
		-nostartfiles \
		-shared \
		-x c /dev/null \
		-o $SYSROOT/usr/lib/libc.so 2>&1 | tee "$LOGDIR/$OBJ""_dummy_libc.log"
	do_msg $OBJ "done"
	touch $BUILDDIR/$OBJ.done
	popd
}

glibc() {
	OBJ=$GLIBC
	do_msg $OBJ "start"
	check_done $OBJ && return 0
	mkdir -p $BUILDDIR/$OBJ
	pushd  $BUILDDIR/$OBJ
	if [ ! -f Makefile ]; then
	    BUILD_CC=gcc \
	    CC=$TOOLCHAIN/bin/$TARGET-gcc \
	    CXX=$TOOLCHAIN/bin/$TARGET-g++ \
        AR=$TOOLCHAIN/bin/$TARGET-ar \
        RANLIB=$TOOLCHAIN/bin/$TARGET-ranlib \
		$WORKDIR/$GLIBC/configure \
		--prefix=/usr \
		--with-headers=$SYSROOT/usr/include \
        --build=$BUILD \
        --host=$TARGET \
        --disable-nls \
        --disable-profile \
        --without-gd \
        --without-cvs \
        --enable-add-ons=nptl,ports\
        --enable-shared \
        --enable-kernel=$(echo $KERNEL | cut -d "-" -f2) \
        libc_cv_forced_unwind=yes \
        libc_cv_c_cleanup=yes
	fi
	do_msg $OBJ "compile"
	PATH=$TOOLCHAIN/bin:$PATH \
	make $PARALLEL 2>&1 | tee "$LOGDIR/$OBJ""_make.log"
	do_msg $OBJ "install"
	PATH=$TOOLCHAIN/bin:$PATH \
	make install install_root=$SYSROOT 2>&1 | tee "$LOGDIR/$OBJ""_make_install.log"
	do_msg $OBJ "done"
	touch $BUILDDIR/$OBJ.done
	popd
}



####################
#### SETUP TIME ####
####################

mkdir -p $LOGDIR
COMMAND_LOG="$LOGDIR/command.log"
echo "" > $COMMAND_LOG

set_default_shell


for arg in "$@"
do
    if [ "$arg" == "--help" ] || [ "$arg" == "-h" ]
    then
        echo "Help argument detected."
    fi
done


# Install missing packages. (Not yet sure if we need libelf-dev)
install_missing_package "build-essential"
install_missing_package "texinfo"
install_missing_package "autoconf"
install_missing_package "gperf"
#install_missing_package "libelf-dev"

# Remove existing, contaminated directories.
echo -e "$STAT Removing any existing build or work dirs..."
echo "rm -rf $BUILDDIR" >> $COMMAND_LOG
rm -rf $BUILDDIR
#echo "rm -rf $WORKDIR" >> $COMMAND_LOG
#rm -rf $WORKDIR
echo "rm -f $LOGDIR/*" >> $COMMAND_LOG
rm -f $LOGDIR/*

# Create necessary directories to work with.
make_dir $SYSROOT
make_dir $TOOLCHAIN
make_dir $SRCDIR
make_dir $WORKDIR
make_dir $BUILDDIR



#######################
#### DOWNLOAD TIME ####
#######################

# Download fresh source files from the internet.
echo -e "$STAT Downloading source files..."
pushd $SRCDIR
get_url "https://ftp.gnu.org/gnu/binutils/$BINUTILS.tar.bz2"
get_url "https://ftp.gnu.org/gnu/gcc/$GCC/$GCC.tar.bz2"
#get_url "https://osmocom.org/attachments/download/2798/patch-gcc46-texi.diff"
get_url "https://mirrors.edge.kernel.org/pub/linux/kernel/v2.6/$KERNEL.tar.bz2"
get_url "https://ftp.gnu.org/gnu/gmp/$GMP.tar.gz"	
get_url "https://ftp.gnu.org/gnu/mpfr/$MPFR.tar.gz"
get_url "https://gcc.gnu.org/pub/gcc/infrastructure/$MPC.tar.gz"
get_url "https://ftp.gnu.org/gnu/libc//$GLIBC.tar.gz"
get_url "https://ftp.gnu.org/gnu/libc/$GLIBCPORTS.tar.gz"
#get_url "www.linuxfromscratch.org/patches/downloads/glibc/glibc-2.11.1-gcc_fix-1.patch"



########################
#### UNZIP TIME UwU ####
########################

# Unpack binutils and gcc
unpack "$BINUTILS.tar.bz2"
unpack "$GCC.tar.bz2"
unpack "$KERNEL.tar.bz2"
unpack "$GLIBC.tar.gz"
unpack "$GMP.tar.gz" "$WORKDIR/$GCC" "gmp"
unpack "$MPFR.tar.gz" "$WORKDIR/$GCC" "mpfr"
unpack "$MPC.tar.gz" "$WORKDIR/$GCC" "mpc"
unpack "$GLIBCPORTS.tar.gz" "$WORKDIR/$GLIBC" "ports"



####################
#### PATCH TIME ####
####################
# Some of these patches are totally understandable - it's been a decade since this version
# of gcc was released (4.5.1). Other patches have me all "How in the fuck did this happen?".
# Like, comment, and subscribe if you agree.
# 
# Patching texinfo issues affecting gcc: https://osmocom.org/issues/1916
# Not really sure how the syntax gets fucked up in only a few places...
do_patch $WORKDIR/$GCC/gcc/doc/gcc.texi $SRCDIR/patch-gcc46-texi.diff
do_patch $WORKDIR/$GCC/gcc/doc/cppopts.texi $SRCDIR/patch-cppopts.texi.diff
do_patch $WORKDIR/$GCC/gcc/doc/invoke.texi $SRCDIR/patch-invoke-texi.diff
do_patch $WORKDIR/$GCC/gcc/doc/generic.texi $SRCDIR/patch-generic-texi.diff

# TODO: Unsure if these two should be patched or if installing gperf is the answer.
# patch-gcc-cfns-gperf.diff is necessary
# https://github.com/parallaxinc/propgcc/issues/79
do_patch $WORKDIR/$GCC/gcc/cp/cfns.h $SRCDIR/patch-gcc-cfns.diff
do_patch $WORKDIR/$GCC/gcc/cp/cfns.gperf $SRCDIR/patch-gcc-cfns-gperf.diff


# Apply some patches because we're dirty futurers.
# Some patches modified and taken from: http://www.linuxfromscratch.org/patches/downloads/glibc/
do_patch $WORKDIR/$GLIBC/manual/Makefile $SRCDIR/patch-glibc-Makefile.diff
do_patch $WORKDIR/$GLIBC/nptl/sysdeps/pthread/pt-initfini.c $SRCDIR/patch-glibc-pt-initfini-c.diff
do_patch $WORKDIR/$GLIBC/sysdeps/unix/sysv/linux/i386/sysdep.h $SRCDIR/patch-glibc-sysdep-h.diff
# Patching configure because we're from the future.
do_patch $WORKDIR/$GLIBC/configure $SRCDIR/patch-glibc-configure.diff


####################
#### BUILD TIME ####
####################

# Compile binutils.
#echo "[*] Compiling $BINUTILS..."
binutils

# Compile the static gcc, and create libgcc_eh.a as a link to libgcc.a
# Because http://www.linuxfromscratch.org/lfs/view/6.7/chapter05/gcc-pass1.html told us to.
# TODO: there may be an issue with where this symbolic link is placed and what path is in PATH
gccstatic

# Compile the kernel headers.
kernelheader

# Compile the glibc headers (I have no idea what I'm doing).
glibcheader

glibc
gccminimal
gccfull

success_message

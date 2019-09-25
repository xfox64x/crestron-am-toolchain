#!/bin/bash 
set -e
set -u

# This directory is used as root for all operations
BASE=$(dirname "$0")
BASE=$(cd "$BASE" && pwd)

# target machine tuple. This is suitable for the marvell sheevaplug
TARGET=arm-unknown-linux-gnueabi
BUILD=$(gcc -dumpmachine)        # x86_64-unknown-linux-gnu, i686-linux-gnu, ...
ARCH=arm

SYSROOT="$BASE/sysroot"     # files for the target system 
TOOLCHAIN="$BASE/toolchain" # the cross compilers
SRCDIR="$BASE/src"          # saving tarballs
WORKDIR="$BASE/work"        # unpacked tarballs
BUILDDIR="$BASE/build"      # running compile 
LOGDIR="$BASE/logs"

PARALLEL="-j2"              # dualcore

# Software Versions to use
BINUTILS=binutils-2.20.1
KERNEL=linux-2.6.32.9
GCC=gcc-4.5.1
GMP=gmp-4.3.1
MPC=mpc-0.8.1
MPFR=mpfr-2.4.2
EGLIBC=eglibc-2_11          # abi compatible to glibc, better support for arm

GREEN="\e[38;5;118m"
RED="\e[38;5;203m"
GREY="\e[38;5;245m"
YELLOW="\e[38;5;208m"
END="\e[0m"
 
GOOD="[$GREEN+$END]"
BAD="[$RED-$END]"
STAT="[$GREY*$END]"
WARN="[$YELLOW!$END]"

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
            echo -e "$BAD$RED""FAILED TO INSTALL REQUIRED PACKAGE!! PLEASE ABORT!!"
        fi
    else
        PACKAGE_VERSION=$(dpkg-query -W --showformat='${Version}' $PACKAGE_NAME)
        echo -e " $GREEN$PACKAGE_NAME=$PACKAGE_VERSION$END"
    fi
}

# download functions
get_url() {
	# pass a full url as parameter
	url=$1
	file=${url##*/}
	if [ ! -f "$SRCDIR/$file" ]; then
		echo "downloading $file from $url"
		echo "wget \"$url\" -O \"$BASE/src/$file\"" >> $COMMAND_LOG
		wget "$url" -O "$BASE/src/$file"
	fi
}

unpack() {
	# pass a filename as parameter
	file=$1
	ext=${file##*.}
	folder=${file%%.tar.*}
	if [ !  -d "$WORKDIR/$folder"  ]; then
		echo -e "$STAT unpacking $file..."
	else
		return 0
	fi
	echo "cd $WORKDIR" >> $COMMAND_LOG
	cd $WORKDIR
	if [ $ext == "bz2" ]; then
		echo "tar jxf \"$SRCDIR/$file\"" >> $COMMAND_LOG
		tar jxf "$SRCDIR/$file"
	else
		echo "tar zxf \"$SRCDIR/$file\"" >> $COMMAND_LOG
		tar zxf "$SRCDIR/$file"
	fi
}

check_done() {
	OBJ=$1
	if [ -f $BUILDDIR/$OBJ.done ]; then
		echo "already done"
		return 0
	fi
	return 1
}

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
	echo "$WORKDIR/$OBJ/configure --target=$TARGET --prefix=$TOOLCHAIN --with-sysroot=$SYSROOT --disable-nls --disable-werror"
	if [ ! -f Makefile ]; then
	    echo "$WORKDIR/$OBJ/configure --target=$TARGET --prefix=$TOOLCHAIN --with-sysroot=$SYSROOT --disable-nls --disable-werror" >> $COMMAND_LOG
		$WORKDIR/$OBJ/configure \
			--target=$TARGET \
			--prefix=$TOOLCHAIN \
			--with-sysroot=$SYSROOT \
			--disable-nls \
			--disable-werror
	fi
	do_msg $OBJ "do make"
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
			--without-cloog
	fi
	do_msg $OBJ "do make"
	echo "PATH=$TOOLCHAIN/bin:$PATH make $PARALLEL 2>&1 | tee $LOGDIR/$OBJ""_make.log" >> $COMMAND_LOG
	PATH=$TOOLCHAIN/bin:$PATH \
	make $PARALLEL 2>&1 | tee "$LOGDIR/$OBJ""_make.log"
	do_msg $OBJ "do make install to $TOOLCHAIN/$TARGET"
	echo "PATH=$TOOLCHAIN/bin:$PATH make install 2>&1 | tee $LOGDIR/$OBJ""_make_install.log" >> $COMMAND_LOG
	PATH=$TOOLCHAIN/bin:$PATH \
	make install 2>&1 | tee "$LOGDIR/$OBJ""_make_install.log" 
	do_msg $OBJ "done"
	touch $BUILDDIR/$OBJ.done
	echo "touch $BUILDDIR/$OBJ.done" >> $COMMAND_LOG
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
			--disable-nls \
			--enable-languages=c 
	# now with shared libs and threads
	fi
	do_msg $OBJ "compile"
	PATH=$TOOLCHAIN/bin:$PATH \
	make $PARALLEL 2>&1 | tee $BUILDDIR/$OBJ/make.log
	do_msg $OBJ "install"
	PATH=$TOOLCHAIN/bin:$PATH \
	make install 2>&1 | tee $BUILDDIR/$OBJ/make_install.log 
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
			--disable-nls 
	# now with c++
	# the cxy_atexit is special for eglibc
	fi
	do_msg $OBJ "compile"
	PATH=$TOOLCHAIN/bin:$PATH \
	make $PARALLEL 2>&1 | tee $BUILDDIR/$OBJ/make.log
	do_msg $OBJ "install"
	PATH=$TOOLCHAIN/bin:$PATH \
	make install 2>&1 | tee $BUILDDIR/$OBJ/make_install.log 
	do_msg $OBJ "done"
	touch $BUILDDIR/$OBJ.done
	popd
}

kernelheader() {
	# compiling headers that work on the target system
	# this is done in-tree 
	OBJ=$KERNEL
	check_done $OBJ && return 0
	pushd $WORKDIR/$OBJ
	do_msg $OBJ "Starting Linux header make"
	make mrproper
	do_msg $OBJ "Installing toolchain headers"
	PATH=$TOOLCHAIN/bin:$PATH \
	make \
		ARCH=$ARCH \
		INSTALL_HDR_PATH=$SYSROOT/usr \
		CROSS_COMPILE=$TARGET- \
		headers_install 
	do_msg $OBJ "done"
	touch $BUILDDIR/$OBJ.done
	popd
}

eglibcheader() {
	OBJ=$EGLIBC-header
	do_msg $OBJ "start"
	check_done $OBJ && return 0
	mkdir -p $BUILDDIR/$OBJ
	pushd $BUILDDIR/$OBJ
	if [ ! -f Makefile ]; then
		BUILD_CC=gcc \
		CC=$TOOLCHAIN/bin/$TARGET-gcc \
		CXX=$TOOLCHAIN/bin/$TARGET-g++ \
		AR=$TOOLCHAIN/bin/$TARGET-ar \
		LD=$TOOLCHAIN/bin/$TARGET-ld \
		RANLIB=$TOOLCHAIN/bin/$TARGET-ranlib \
		$WORKDIR/$EGLIBC/configure \
			--prefix=/usr \
			--with-headers=$SYSROOT/usr/include \
			--build=$BUILD \
			--host=$TARGET \
			--disable-nls \
			--disable-profile \
			--without-gd \
			--without-cvs \
			--enable-add-ons
	fi
	do_msg $OBJ "install"
	make \
		install-headers \
		install_root=$SYSROOT \
		install-bootstrap-headers=yes
	do_msg $OBJ "crtX and fake libc"
	make csu/subdir_lib
	mkdir -p $SYSROOT/usr/lib
	cp csu/crt1.o csu/crti.o csu/crtn.o $SYSROOT/usr/lib
	# build a dummy libc
	$TOOLCHAIN/bin/$TARGET-gcc \
		-nostdlib \
		-nostartfiles \
		-shared \
		-x c /dev/null \
		-o $SYSROOT/usr/lib/libc.so
	do_msg $OBJ "done"
	touch $BUILDDIR/$OBJ.done
	popd
}
eglibc() {
	OBJ=$EGLIBC
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
		$WORKDIR/$EGLIBC/configure \
			--prefix=/usr \
			--with-headers=$SYSROOT/usr/include \
			--build=$BUILD \
			--host=$TARGET \
			--disable-nls \
			--disable-profile \
			--without-gd \
			--without-cvs \
			--enable-add-ons
	fi
	do_msg $OBJ "compile"
	PATH=$TOOLCHAIN/bin:$PATH \
	make $PARALLEL
	do_msg $OBJ "install"
	PATH=$TOOLCHAIN/bin:$PATH \
	make install install_root=$SYSROOT
	do_msg $OBJ "done"
	touch $BUILDDIR/$OBJ.done
	popd
}



# ==============================================
# MAIN
# ==============================================
mkdir -p $LOGDIR
COMMAND_LOG="$LOGDIR/command.log"
echo "" > $COMMAND_LOG

install_missing_package "build-essential"
install_missing_package "texinfo"
#install_missing_package "libelf-dev"

echo -e "$STAT Removing any existing build or work dirs..."
echo "rm -rf $BUILDDIR" >> $COMMAND_LOG
rm -rf $BUILDDIR
echo "rm -rf $WORKDIR" >> $COMMAND_LOG
rm -rf $WORKDIR
#echo "rm -rf $LOGDIR" >> $COMMAND_LOG
#rm -rf $LOGDIR
#rm -rf $SYSROOT
#rm -rf $TOOLCHAIN
#rm -rf $SRCDIR

echo -e "$STAT Creating directories..."
echo "mkdir -p $BUILDDIR" >> $COMMAND_LOG
mkdir -p $BUILDDIR
echo "mkdir -p $WORKDIR" >> $COMMAND_LOG
mkdir -p $WORKDIR
echo "mkdir -p $SRCDIR" >> $COMMAND_LOG
mkdir -p $SRCDIR
echo "mkdir -p $SYSROOT" >> $COMMAND_LOG
mkdir -p $SYSROOT
echo "mkdir -p $TOOLCHAIN" >> $COMMAND_LOG
mkdir -p $TOOLCHAIN

echo -e "$STAT Downloading source files..."
pushd $SRCDIR
#get_url "https://ftp.gnu.org/gnu/binutils/$BINUTILS.tar.bz2"
#get_url "https://ftp.gnu.org/gnu/gcc/$GCC/$GCC.tar.bz2"
get_url "https://osmocom.org/attachments/download/2798/patch-gcc46-texi.diff"
#get_url "https://mirrors.edge.kernel.org/pub/linux/kernel/v2.6/$KERNEL.tar.bz2"
#get_url "https://ftp.gnu.org/gnu/gmp/$GMP.tar.gz"	
#get_url "https://ftp.gnu.org/gnu/mpfr/$MPFR.tar.gz"
#get_url "https://gcc.gnu.org/pub/gcc/infrastructure/$MPC.tar.gz"

echo -e "$STAT Unpacking source files into working directories..."
unpack "$BINUTILS.tar.bz2"
unpack "$GCC.tar.bz2"

do_msg $GCC "Applying GCC docs gcc.texi patch..."
echo "patch $WORKDIR/$GCC/gcc/doc/gcc.texi $SRCDIR/patch-gcc46-texi.diff" >> $COMMAND_LOG
#cp $WORKDIR/$GCC/gcc/doc/gcc.texi $WORKDIR/$GCC/gcc/doc/gcc.texi.back
patch $WORKDIR/$GCC/gcc/doc/gcc.texi $SRCDIR/patch-gcc46-texi.diff
echo "patch $WORKDIR/$GCC/gcc/doc/cppopts.texi $SRCDIR/patch-cppopts.texi.diff" >> $COMMAND_LOG
patch $WORKDIR/$GCC/gcc/doc/cppopts.texi $SRCDIR/patch-cppopts.texi.diff
echo "patch $WORKDIR/$GCC/gcc/doc/invoke.texi $SRCDIR/patch-invoke-texi.diff" >> $COMMAND_LOG
patch $WORKDIR/$GCC/gcc/doc/invoke.texi $SRCDIR/patch-invoke-texi.diff

echo -e "$STAT Unpacking and renaming $GCC requirements..."
echo "cp $SRCDIR/$GMP.tar.gz $WORKDIR/$GCC" >> $COMMAND_LOG
cp $SRCDIR/$GMP.tar.gz $WORKDIR/$GCC
echo "cp $SRCDIR/$MPFR.tar.gz $WORKDIR/$GCC" >> $COMMAND_LOG
cp $SRCDIR/$MPFR.tar.gz $WORKDIR/$GCC
echo "cp $SRCDIR/$MPC.tar.gz $WORKDIR/$GCC" >> $COMMAND_LOG
cp $SRCDIR/$MPC.tar.gz $WORKDIR/$GCC

echo "cd $WORKDIR/$GCC" >> $COMMAND_LOG
cd $WORKDIR/$GCC

echo "tar zxf $GMP.tar.gz" >> $COMMAND_LOG
tar zxf $GMP.tar.gz
echo "tar zxf $MPFR.tar.gz" >> $COMMAND_LOG
tar zxf $MPFR.tar.gz
echo "tar zxf $MPC.tar.gz" >> $COMMAND_LOG
tar zxf $MPC.tar.gz
echo "mv -v $GMP gmp" >> $COMMAND_LOG
mv -v $GMP gmp
echo "mv -v $MPFR mpfr" >> $COMMAND_LOG
mv -v $MPFR mpfr
echo "mv -v $MPC mpc" >> $COMMAND_LOG
mv -v $MPC mpc
echo "cd $BASE" >> $COMMAND_LOG
cd $BASE

echo -e "$GOOD Finished unpacking and renaming $GCC requirements."
echo -e "$STAT Unpacking Linux headers for $KERNEL..."
unpack "$KERNEL.tar.bz2"

#if [ ! -h $WORKDIR/$EGLIBC ]; then
#	ln -s $SRCDIR/$EGLIBC $WORKDIR/$EGLIBC
#fi

#echo "[*] Compiling $BINUTILS..."
#binutils
echo -e "$STAT Compiling $GCC static binaries..."
gccstatic

#ln -vs libgcc.a `$TARGET-gcc -print-libgcc-file-name | sed 's/libgcc/&_eh/'`

#kernelheaderll
#eglibcheader
#gccminimal
#eglibc
#gccfull

echo -e "$GREEN"
echo "     _                   "
echo "  __| | ___  _ __   ___  "
echo " / _  |/ _ \| '_ \ / _ \ "
echo "| (_| | (_) | | | |  __/ "
echo " \__,_|\___/|_| |_|\___| "
echo "                         "
echo -e "$END"

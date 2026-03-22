#!/usr/bin/env bash
[ -z "$PHP_VERSION" ] && PHP_VERSION="8.2.13"

ZLIB_VERSION="1.3"
GMP_VERSION="6.3.0"
CURL_VERSION="curl-8_5_0"
YAML_VERSION="0.2.5"
LEVELDB_VERSION="1c7564468b41610da4f498430e795ca4de0931ff"
LIBXML_VERSION="2.10.1"
LIBPNG_VERSION="1.6.40"
LIBJPEG_VERSION="9e"
OPENSSL_VERSION="3.1.4"
LIBZIP_VERSION="1.10.1"
SQLITE3_VERSION="3440200"
LIBDEFLATE_VERSION="dd12ff2b36d603dbb7fa8838fe7e7176fcbd4f6f"

EXT_PMMPTHREAD_VERSION="6.0.12"
EXT_YAML_VERSION="2.2.3"
EXT_LEVELDB_VERSION="0.2.1"
EXT_CHUNKUTILS2_VERSION="0.3.5"
EXT_XDEBUG_VERSION="3.3.0"
EXT_IGBINARY_VERSION="3.2.15"
EXT_CRYPTO_VERSION="0.3.2"
EXT_RECURSIONGUARD_VERSION="0.1.0"
EXT_LIBDEFLATE_VERSION="0.2.1"
EXT_MORTON_VERSION="0.1.2"
EXT_XXHASH_VERSION="0.2.0"
EXT_ARRAYDEBUG_VERSION="0.2.0"
EXT_ENCODING_VERSION="0.2.3"

function write_out {
	echo "[$1] $2"
}

function write_error {
	write_out ERROR "$1" >&2
}

function write_status {
	echo -n " $1..."
}

function write_library {
  echo -n "[$1 $2]"
}

function write_caching {
  write_status "using cache"
}

function write_download {
	write_status "downloading"
}
function write_configure {
	write_status "configuring"
}
function write_compile {
	write_status "compiling"
}
function write_install {
	write_status "installing"
}
function write_done {
	echo " done!"
}
function cant_use_cache {
	if [ -f "$1/.compile.sh.cache" ]; then
		return 1
	else
		return 0
	fi
}
function mark_cache {
	touch "./.compile.sh.cache"
}

write_out "PocketMine-MP 5" "PHP 8.2.13 compiler for Linux x86_64"
DIR="$(pwd)"
BASE_BUILD_DIR="$DIR/install_data"
BUILD_DIR="$BASE_BUILD_DIR/subdir"
LIB_BUILD_DIR="$BUILD_DIR/lib"
INSTALL_DIR="$DIR/bin/php7"
SYMBOLS_DIR="$DIR/bin-debug/php7"

date > "$DIR/install.log" 2>&1

uname -a >> "$DIR/install.log" 2>&1
write_out "INFO" "Checking dependencies"

COMPILE_SH_DEPENDENCIES=( make autoconf automake m4 getconf gzip bzip2 bison g++ git cmake pkg-config re2c libtool)
ERRORS=0
for(( i=0; i<${#COMPILE_SH_DEPENDENCIES[@]}; i++ ))
do
	type "${COMPILE_SH_DEPENDENCIES[$i]}" >> "$DIR/install.log" 2>&1 || { write_error "Please install \"${COMPILE_SH_DEPENDENCIES[$i]}\""; ((ERRORS++)); }
done

type wget >> "$DIR/install.log" 2>&1 || type curl >> "$DIR/install.log" || { write_error "Please install \"wget\" or \"curl\""; ((ERRORS++)); }

type libtool >> "$DIR/install.log" 2>&1 || { write_error "Please install \"libtool\" or \"libtool-bin\""; ((ERRORS++)); }
export LIBTOOL=libtool
export LIBTOOLIZE=libtoolize

if [ $ERRORS -ne 0 ]; then
	exit 1
fi

export CC="gcc"
export CXX="g++"
export RANLIB=ranlib

COMPILE_FOR_ANDROID=no
HAVE_MYSQLI="--enable-mysqlnd --with-mysqli=mysqlnd"
COMPILE_TARGET=""
IS_CROSSCOMPILE="no"
IS_WINDOWS="no"
DO_OPTIMIZE="yes"
DO_STATIC="no"
DO_CLEANUP="yes"
COMPILE_DEBUG="no"
HAVE_VALGRIND="--without-valgrind"
HAVE_OPCACHE="yes"
HAVE_XDEBUG="yes"
FSANITIZE_OPTIONS=""
FLAGS_LTO=""
HAVE_OPCACHE_JIT="no"

COMPILE_GD="no"

PM_VERSION_MAJOR=""

DOWNLOAD_INSECURE="no"
DOWNLOAD_CACHE=""
SEPARATE_SYMBOLS="no"

while getopts "::t:j:sdDxfgnva:P:c:l:Ji" OPTION; do

	case $OPTION in
		l)
			mkdir "$OPTARG" 2> /dev/null
			LIB_BUILD_DIR="$(cd $OPTARG; pwd)"
			write_out opt "Reusing previously built libraries in $LIB_BUILD_DIR if found"
			write_out WARNING "Reusing previously built libraries may break if different args were used!"
			;;
		c)
			mkdir "$OPTARG" 2> /dev/null
			DOWNLOAD_CACHE="$(cd $OPTARG; pwd)"
			write_out opt "Caching downloaded files in $DOWNLOAD_CACHE and reusing if available"
			;;
		t)
			write_out "opt" "Set target to $OPTARG"
			COMPILE_TARGET="$OPTARG"
			;;
		j)
			write_out "opt" "Set make threads to $OPTARG"
			THREADS="$OPTARG"
			;;
		d)
			write_out "opt" "Will compile everything with debugging symbols, will not remove sources"
			COMPILE_DEBUG="yes"
			DO_CLEANUP="no"
			DO_OPTIMIZE="no"
			CFLAGS="$CFLAGS -g"
			CXXFLAGS="$CXXFLAGS -g"
			;;
		D)
			write_out "opt" "Compiling with separated debugging symbols, but leaving optimizations enabled"
			SEPARATE_SYMBOLS="yes"
			CFLAGS="$CFLAGS -g"
			CXXFLAGS="$CXXFLAGS -g"
			;;
		x)
			write_out "opt" "Doing cross-compile"
			IS_CROSSCOMPILE="yes"
			;;
		s)
			write_out "opt" "Will compile everything statically"
			DO_STATIC="yes"
			CFLAGS="$CFLAGS -static"
			;;
		f)
			write_out "deprecated" "The -f flag is deprecated, as optimizations are now enabled by default unless -d (debug mode) is specified"
			;;
		g)
			write_out "opt" "Will enable GD2"
			COMPILE_GD="yes"
			;;
		n)
			write_out "opt" "Will not remove sources after completing compilation"
			DO_CLEANUP="no"
			;;
		v)
			write_out "opt" "Will enable valgrind support in PHP"
			HAVE_VALGRIND="--with-valgrind"
			;;
		a)
			write_out "opt" "Will pass -fsanitize=$OPTARG to compilers and linkers"
			FSANITIZE_OPTIONS="$OPTARG"
			;;
		P)
			PM_VERSION_MAJOR="$OPTARG"
			;;
		J)
			write_out "opt" "Compiling JIT support in OPcache (unstable)"
			HAVE_OPCACHE_JIT="yes"
			;;
		i)
			write_out "opt" "Disabling SSL certificate verification for downloads"
			write_out "WARNING" "This is a security risk, please only use this if you know what you are doing!"
			DOWNLOAD_INSECURE="yes"
			;;
		\?)
			write_error "Invalid option: -$OPTARG"
			exit 1
			;;
	esac
done

if [ "$PM_VERSION_MAJOR" == "" ]; then
	write_error "Please specify PocketMine-MP major version target with -P (e.g. -P5)"
	exit 1
fi

write_out "opt" "Compiling with configuration for PocketMine-MP $PM_VERSION_MAJOR"

shopt -s expand_aliases
type wget >> "$DIR/install.log" 2>&1
if [ $? -eq 0 ]; then
	wget_flags=""
	if [ "$DOWNLOAD_INSECURE" == "yes" ]; then
		wget_flags="--no-check-certificate"
	fi
	alias _download_file="wget $wget_flags -nv -O -"
else
	type curl >> "$DIR/install.log" 2>&1
	if [ $? -eq 0 ]; then
		curl_flags=""
		if [ "$DOWNLOAD_INSECURE" == "yes" ]; then
			curl_flags="--insecure"
		fi
		alias _download_file="curl $curl_flags --silent --show-error --location --globoff"
	else
		write_error "Neither curl nor wget found. Please install one and try again."
		exit 1
	fi
fi

function download_file {
	local url="$1"
	local prefix="$2"
	local cached_filename="$prefix-${url##*/}"

	if [[ "$DOWNLOAD_CACHE" != "" ]]; then
		if [[ ! -d "$DOWNLOAD_CACHE" ]]; then
			mkdir "$DOWNLOAD_CACHE" >> "$DIR/install.log" 2>&1
		fi
		if [[ -f "$DOWNLOAD_CACHE/$cached_filename" ]]; then
			echo "Cache hit for URL: $url" >> "$DIR/install.log"
		else
			echo "Downloading file to cache: $url" >> "$DIR/install.log"
			_download_file "$1" > "$DOWNLOAD_CACHE/$cached_filename" 2>> "$DIR/install.log"
		fi
		cat "$DOWNLOAD_CACHE/$cached_filename" 2>> "$DIR/install.log"
	else
		echo "Downloading non-cached file: $url" >> "$DIR/install.log"
		_download_file "$1" 2>> "$DIR/install.log"
	fi
}

function download_from_mirror {
	download_file "https://github.com/pmmp/DependencyMirror/releases/download/mirror/$1" "$2"
}

function download_github_src {
	download_file "https://github.com/$1/archive/$2.tar.gz" "$3"
}

GMP_ABI="64"
OPENSSL_TARGET="linux-x86_64"

write_out "INFO" "Compiling for Linux x86_64"
[ -z "$march" ] && march=x86-64;
[ -z "$mtune" ] && mtune=skylake;
CFLAGS="$CFLAGS -m64"

if [ -z "$THREADS" ]; then
	write_out "WARNING" "Only 1 thread is used by default. Increase thread count using -j (e.g. -j 4) to compile faster."	
	THREADS=1;
fi
[ -z "$CFLAGS" ] && CFLAGS="";

if [ "$DO_STATIC" == "no" ]; then
	[ -z "$LDFLAGS" ] && LDFLAGS="-Wl,-rpath='\$\$ORIGIN/../lib' -Wl,-rpath-link='\$\$ORIGIN/../lib'";
fi

[ -z "$CONFIGURE_FLAGS" ] && CONFIGURE_FLAGS="";

if [ "$mtune" != "none" ]; then
	$CC -march=$march -mtune=$mtune $CFLAGS -o test test.c >> "$DIR/install.log" 2>&1
	if [ $? -eq 0 ]; then
		CFLAGS="-march=$march -mtune=$mtune $CFLAGS"
	fi
else
	$CC -march=$march $CFLAGS -o test test.c >> "$DIR/install.log" 2>&1
	if [ $? -eq 0 ]; then
		CFLAGS="-march=$march $CFLAGS"
	fi
fi

if [ "$DO_OPTIMIZE" != "no" ]; then
	CFLAGS="$CFLAGS -O2"
	GENERIC_CFLAGS="$CFLAGS -ftree-vectorize -fomit-frame-pointer"
	$CC $CFLAGS $GENERIC_CFLAGS -o test test.c >> "$DIR/install.log" 2>&1
	if [ $? -eq 0 ]; then
		CFLAGS="$CFLAGS $GENERIC_CFLAGS"
	fi
	GCC_CFLAGS="$CFLAGS -funsafe-loop-optimizations -fpredictive-commoning -ftracer -ftree-loop-im -frename-registers -fcx-limited-range -funswitch-loops -fivopts -fno-gcse"
	$CC $CFLAGS $GCC_CFLAGS -o test test.c >> "$DIR/install.log" 2>&1
	if [ $? -eq 0 ]; then
		CFLAGS="$CFLAGS $GCC_CFLAGS"
	fi
fi

if [ "$FSANITIZE_OPTIONS" != "" ]; then
	CFLAGS="$CFLAGS" CXXFLAGS="$CXXFLAGS" LDFLAGS="$LDFLAGS" $CC -fsanitize=$FSANITIZE_OPTIONS -o asan-test test.c >> "$DIR/install.log" 2>&1 && \
		chmod +x asan-test >> "$DIR/install.log" 2>&1 && \
		./asan-test >> "$DIR/install.log" 2>&1 && \
		rm asan-test >> "$DIR/install.log" 2>&1
	if [ $? -ne 0 ]; then
		write_out "ERROR" "One or more sanitizers are not working. Check install.log for details."
		exit 1
	else
		write_out "INFO" "All selected sanitizers are working"
	fi
fi

rm test.* >> "$DIR/install.log" 2>&1
rm test >> "$DIR/install.log" 2>&1

export CC="$CC"
export CXX="$CXX"
export CFLAGS="-O2 -fPIC $CFLAGS"
export CXXFLAGS="$CFLAGS $CXXFLAGS"
export LDFLAGS="$LDFLAGS"
export CPPFLAGS="$CPPFLAGS"
export LIBRARY_PATH="$INSTALL_DIR/lib:$LIBRARY_PATH"
export PKG_CONFIG_PATH="$INSTALL_DIR/lib/pkgconfig"

export PKG_CONFIG_ALLOW_SYSTEM_LIBS="yes"
export PKG_CONFIG_ALLOW_SYSTEM_CFLAGS="yes"

rm -r -f "$BASE_BUILD_DIR" >> "$DIR/install.log" 2>&1
rm -r -f bin/ >> "$DIR/install.log" 2>&1
mkdir -m 0755 "$BASE_BUILD_DIR" >> "$DIR/install.log" 2>&1
mkdir -m 0755 "$BUILD_DIR" >> "$DIR/install.log" 2>&1
mkdir -m 0755 -p $INSTALL_DIR >> "$DIR/install.log" 2>&1
mkdir -m 0755 -p "$LIB_BUILD_DIR" >> "$DIR/install.log" 2>&1
cd "$BUILD_DIR"
set -e

write_library "PHP" "$PHP_VERSION"
write_download

download_github_src "php/php-src" "php-$PHP_VERSION" "php" | tar -zx >> "$DIR/install.log" 2>&1
mv php-src-php-$PHP_VERSION php
write_done

function build_zlib {
	if [ "$DO_STATIC" == "yes" ]; then
		local EXTRA_FLAGS="--static"
	else
		local EXTRA_FLAGS="--shared"
	fi

	write_library zlib "$ZLIB_VERSION"
	local zlib_dir="./zlib-$ZLIB_VERSION"

	if cant_use_cache "$zlib_dir"; then
		rm -rf "$zlib_dir"
		write_download
		download_github_src "madler/zlib" "v$ZLIB_VERSION" "zlib" | tar -zx >> "$DIR/install.log" 2>&1
		write_configure
		cd "$zlib_dir"
		RANLIB=$RANLIB ./configure --prefix="$INSTALL_DIR" \
		$EXTRA_FLAGS >> "$DIR/install.log" 2>&1
		write_compile
		make -j $THREADS >> "$DIR/install.log" 2>&1 && mark_cache
	else
		write_caching
		cd "$zlib_dir"
	fi
	write_install
	make install >> "$DIR/install.log" 2>&1
	cd ..
	if [ "$DO_STATIC" != "yes" ]; then
		rm -f "$INSTALL_DIR/lib/libz.a"
	fi
	write_done
}

function build_gmp {
	export jm_cv_func_working_malloc=yes
	export ac_cv_func_malloc_0_nonnull=yes
	export jm_cv_func_working_realloc=yes
	export ac_cv_func_realloc_0_nonnull=yes

	local EXTRA_FLAGS="--disable-assembly"

	write_library gmp "$GMP_VERSION"
	local gmp_dir="./gmp-$GMP_VERSION"

	if cant_use_cache "$gmp_dir"; then
		rm -rf "$gmp_dir"
		write_download
		download_from_mirror "gmp-$GMP_VERSION.tar.xz" "gmp" | tar -Jx >> "$DIR/install.log" 2>&1
		write_configure
		cd "$gmp_dir"
		RANLIB=$RANLIB ./configure --prefix="$INSTALL_DIR" \
		$EXTRA_FLAGS \
		--disable-posix-threads \
		--enable-static \
		--disable-shared \
		ABI="$GMP_ABI" >> "$DIR/install.log" 2>&1
		write_compile
		make -j $THREADS >> "$DIR/install.log" 2>&1 && mark_cache
	else
		write_caching
		cd "$gmp_dir"
	fi
	write_install
	make install >> "$DIR/install.log" 2>&1
	cd ..
	write_done
}

function build_openssl {
	if [ "$DO_STATIC" == "yes" ]; then
		local EXTRA_FLAGS="no-shared -static"
	else
		local EXTRA_FLAGS="shared"
	fi

	write_library openssl "$OPENSSL_VERSION"
	local openssl_dir="./openssl-openssl-$OPENSSL_VERSION"

	if cant_use_cache "$openssl_dir"; then
		rm -rf "$openssl_dir"
		write_download
		download_github_src "openssl/openssl" "openssl-$OPENSSL_VERSION" "openssl" | tar -zx >> "$DIR/install.log" 2>&1

		write_configure
		cd "$openssl_dir"
		RANLIB=$RANLIB ./Configure $OPENSSL_TARGET \
		--prefix="$INSTALL_DIR" \
		--openssldir="$INSTALL_DIR" \
		--libdir="$INSTALL_DIR/lib" \
		no-asm \
		no-hw \
		no-engine \
		$EXTRA_FLAGS >> "$DIR/install.log" 2>&1

		write_compile
		make -j $THREADS >> "$DIR/install.log" 2>&1 && mark_cache
	else
		write_caching
		cd "$openssl_dir"
	fi
	write_install
	make install_sw >> "$DIR/install.log" 2>&1
	cd ..
	write_done
}

function build_curl {
	if [ "$DO_STATIC" == "yes" ]; then
		local EXTRA_FLAGS="--enable-static --disable-shared"
	else
		local EXTRA_FLAGS="--disable-static --enable-shared"
	fi

	write_library curl "$CURL_VERSION"
	local curl_dir="./curl-$CURL_VERSION"
	if cant_use_cache "$curl_dir"; then
		rm -rf "$curl_dir"
		write_download
		download_github_src "curl/curl" "$CURL_VERSION" "curl" | tar -zx >> "$DIR/install.log" 2>&1
		write_configure
		cd "$curl_dir"
		./buildconf --force >> "$DIR/install.log" 2>&1
		RANLIB=$RANLIB ./configure --disable-dependency-tracking \
		--enable-ipv6 \
		--enable-optimize \
		--enable-http \
		--enable-ftp \
		--disable-dict \
		--enable-file \
		--without-librtmp \
		--disable-gopher \
		--disable-imap \
		--disable-pop3 \
		--disable-rtsp \
		--disable-smtp \
		--disable-telnet \
		--disable-tftp \
		--disable-ldap \
		--disable-ldaps \
		--without-libidn \
		--without-libidn2 \
		--without-brotli \
		--without-nghttp2 \
		--without-zstd \
		--with-zlib="$INSTALL_DIR" \
		--with-ssl="$INSTALL_DIR" \
		--enable-threaded-resolver \
		--prefix="$INSTALL_DIR" \
		$EXTRA_FLAGS >> "$DIR/install.log" 2>&1
		write_compile
		make -j $THREADS >> "$DIR/install.log" 2>&1 && mark_cache
	else
		write_caching
		cd "$curl_dir"
	fi

	write_install
	make install >> "$DIR/install.log" 2>&1
	cd ..
	write_done
}

function build_yaml {
	if [ "$DO_STATIC" == "yes" ]; then
		local EXTRA_FLAGS="--disable-shared --enable-static"
	else
		local EXTRA_FLAGS="--enable-shared --disable-static"
	fi

	write_library yaml "$YAML_VERSION"
	local yaml_dir="./libyaml-$YAML_VERSION"
	if cant_use_cache "$yaml_dir"; then
		rm -rf "$yaml_dir"
		write_download
		download_github_src "yaml/libyaml" "$YAML_VERSION" "yaml" | tar -zx >> "$DIR/install.log" 2>&1
		cd "$yaml_dir"
		./bootstrap >> "$DIR/install.log" 2>&1

		write_configure

		RANLIB=$RANLIB ./configure \
		--prefix="$INSTALL_DIR" \
		$EXTRA_FLAGS >> "$DIR/install.log" 2>&1
		sed -i=".backup" 's/ tests win32/ win32/g' Makefile

		write_compile
		make -j $THREADS all >> "$DIR/install.log" 2>&1 && mark_cache
	else
		write_caching
		cd "$yaml_dir"
	fi
	write_install
	make install >> "$DIR/install.log" 2>&1
	cd ..
	write_done
}

function build_leveldb {
	write_library leveldb "$LEVELDB_VERSION"
	local leveldb_dir="./leveldb-$LEVELDB_VERSION"
	if cant_use_cache "$leveldb_dir"; then
		rm -rf "$leveldb_dir"
		write_download
		download_github_src "pmmp/leveldb" "$LEVELDB_VERSION" "leveldb" | tar -zx >> "$DIR/install.log" 2>&1

		write_configure
		cd "$leveldb_dir"
		if [ "$DO_STATIC" != "yes" ]; then
			local EXTRA_FLAGS="-DBUILD_SHARED_LIBS=ON"
		else
			local EXTRA_FLAGS=""
		fi
		cmake . \
			-DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
			-DCMAKE_PREFIX_PATH="$INSTALL_DIR" \
			-DCMAKE_INSTALL_LIBDIR=lib \
			-DLEVELDB_BUILD_TESTS=OFF \
			-DLEVELDB_BUILD_BENCHMARKS=OFF \
			-DLEVELDB_SNAPPY=OFF \
			-DLEVELDB_ZSTD=OFF \
			-DLEVELDB_TCMALLOC=OFF \
			-DCMAKE_BUILD_TYPE=Release \
			$EXTRA_FLAGS \
			>> "$DIR/install.log" 2>&1

		write_compile
		make -j $THREADS >> "$DIR/install.log" 2>&1 && mark_cache
	else
		write_caching
		cd "$leveldb_dir"
	fi

	write_install
	make install >> "$DIR/install.log" 2>&1
	cd ..
	write_done
}

function build_libpng {
	if [ "$DO_STATIC" == "yes" ]; then
		local EXTRA_FLAGS="--enable-shared=no --enable-static=yes"
	else
		local EXTRA_FLAGS="--enable-shared=yes --enable-static=no"
	fi

	write_library libpng "$LIBPNG_VERSION"
	local libpng_dir="./libpng-$LIBPNG_VERSION"
	if cant_use_cache "$libpng_dir"; then
		rm -rf "$libpng_dir"
		write_download
		download_from_mirror "libpng-$LIBPNG_VERSION.tar.gz" "libpng" | tar -zx >> "$DIR/install.log" 2>&1

		write_configure
		cd "$libpng_dir"
		LDFLAGS="$LDFLAGS -L${INSTALL_DIR}/lib" CPPFLAGS="$CPPFLAGS -I${INSTALL_DIR}/include" RANLIB=$RANLIB ./configure \
		--prefix="$INSTALL_DIR" \
		$EXTRA_FLAGS >> "$DIR/install.log" 2>&1

		write_compile
		make -j $THREADS >> "$DIR/install.log" 2>&1 && mark_cache
	else
		write_caching
		cd "$libpng_dir"
	fi

	write_install
	make install >> "$DIR/install.log" 2>&1
	cd ..
	write_done
}

function build_libjpeg {
	if [ "$DO_STATIC" == "yes" ]; then
		local EXTRA_FLAGS="--enable-shared=no --enable-static=yes"
	else
		local EXTRA_FLAGS="--enable-shared=yes --enable-static=no"
	fi

	write_library libjpeg "$LIBJPEG_VERSION"
	local libjpeg_dir="./libjpeg-$LIBJPEG_VERSION"
	if cant_use_cache "$libjpeg_dir"; then
		rm -rf "$libjpeg_dir"
		write_download
		download_from_mirror "jpegsrc.v$LIBJPEG_VERSION.tar.gz" "libjpeg" | tar -zx >> "$DIR/install.log" 2>&1
		mv jpeg-$LIBJPEG_VERSION "$libjpeg_dir"

		write_configure
		cd "$libjpeg_dir"
		LDFLAGS="$LDFLAGS -L${INSTALL_DIR}/lib" CPPFLAGS="$CPPFLAGS -I${INSTALL_DIR}/include" RANLIB=$RANLIB ./configure \
		--prefix="$INSTALL_DIR" \
		$EXTRA_FLAGS >> "$DIR/install.log" 2>&1

		write_compile
		make -j $THREADS >> "$DIR/install.log" 2>&1 && mark_cache
	else
		write_caching
		cd "$libjpeg_dir"
	fi
	write_install
	make install >> "$DIR/install.log" 2>&1
	cd ..
	write_done
}

function build_libxml2 {
	write_library libxml2 "$LIBXML_VERSION"
	local libxml2_dir="./libxml2-$LIBXML_VERSION"

	if cant_use_cache "$libxml2_dir"; then
		rm -rf "$libxml2_dir"
		write_download
		download_from_mirror "libxml2-v$LIBXML_VERSION.tar.gz" "libxml2" | tar -xz >> "$DIR/install.log" 2>&1
		mv libxml2-v$LIBXML_VERSION "$libxml2_dir"

		write_configure
		cd "$libxml2_dir"
		if [ "$DO_STATIC" == "yes" ]; then
			local EXTRA_FLAGS="--enable-shared=no --enable-static=yes"
		else
			local EXTRA_FLAGS="--enable-shared=yes --enable-static=no"
		fi
		sed -i.bak 's{libtoolize --version{"$LIBTOOLIZE" --version{' autogen.sh
		./autogen.sh --prefix="$INSTALL_DIR" \
			--without-iconv \
			--without-python \
			--without-lzma \
			--with-zlib="$INSTALL_DIR" \
			--config-cache \
			$EXTRA_FLAGS >> "$DIR/install.log" 2>&1

		write_compile
		make -j $THREADS >> "$DIR/install.log" 2>&1 && mark_cache
	else
		write_caching
		cd "$libxml2_dir"
	fi
	write_install
	make install >> "$DIR/install.log" 2>&1
	cd ..
	write_done
}

function build_libzip {
	if [ "$DO_STATIC" == "yes" ]; then
		local CMAKE_LIBZIP_EXTRA_FLAGS="-DBUILD_SHARED_LIBS=OFF"
	fi

	write_library libzip "$LIBZIP_VERSION"
	local libzip_dir="./libzip-$LIBZIP_VERSION"
	if cant_use_cache "$libzip_dir"; then
		rm -rf "$libzip_dir"
		write_download
		download_github_src "nih-at/libzip" "v$LIBZIP_VERSION" "libzip" | tar -zx >> "$DIR/install.log" 2>&1
		write_configure
		cd "$libzip_dir"

		cmake . \
			-DCMAKE_PREFIX_PATH="$INSTALL_DIR" \
			-DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
			-DCMAKE_INSTALL_LIBDIR=lib \
			$CMAKE_LIBZIP_EXTRA_FLAGS \
			-DBUILD_TOOLS=OFF \
			-DBUILD_REGRESS=OFF \
			-DBUILD_EXAMPLES=OFF \
			-DBUILD_DOC=OFF \
			-DENABLE_BZIP2=OFF \
			-DENABLE_COMMONCRYPTO=OFF \
			-DENABLE_GNUTLS=OFF \
			-DENABLE_MBEDTLS=OFF \
			-DENABLE_LZMA=OFF \
			-DENABLE_ZSTD=OFF >> "$DIR/install.log" 2>&1
		write_compile
		make -j $THREADS >> "$DIR/install.log" 2>&1 && mark_cache
	else
		write_caching
		cd "$libzip_dir"
	fi
	write_install
	make install >> "$DIR/install.log" 2>&1
	cd ..
	write_done
}

function build_sqlite3 {
	if [ "$DO_STATIC" == "yes" ]; then
		local EXTRA_FLAGS="--enable-static=yes --enable-shared=no"
	else
		local EXTRA_FLAGS="--enable-static=no --enable-shared=yes"
	fi

	write_library sqlite3 "$SQLITE3_VERSION"
	local sqlite3_dir="./sqlite3-$SQLITE3_VERSION"

	if cant_use_cache "$sqlite3_dir"; then
		rm -rf "$sqlite3_dir"
		write_download
		download_from_mirror "sqlite-autoconf-$SQLITE3_VERSION.tar.gz" "sqlite3" | tar -zx >> "$DIR/install.log" 2>&1
		mv sqlite-autoconf-$SQLITE3_VERSION "$sqlite3_dir" >> "$DIR/install.log" 2>&1
		write_configure
		cd "$sqlite3_dir"
		LDFLAGS="$LDFLAGS -L${INSTALL_DIR}/lib" CPPFLAGS="$CPPFLAGS -I${INSTALL_DIR}/include" RANLIB=$RANLIB ./configure \
		--prefix="$INSTALL_DIR" \
		--disable-dependency-tracking \
		--enable-static-shell=no \
		$EXTRA_FLAGS >> "$DIR/install.log" 2>&1
		write_compile
		make -j $THREADS >> "$DIR/install.log" 2>&1 && mark_cache
	else
		write_caching
		cd "$sqlite3_dir"
	fi
	write_install
	make install >> "$DIR/install.log" 2>&1
	cd ..
	write_done
}

function build_libdeflate {
	write_library libdeflate "$LIBDEFLATE_VERSION"
	local libdeflate_dir="./libdeflate-$LIBDEFLATE_VERSION"

	if [ "$DO_STATIC" == "yes" ]; then
		local CMAKE_LIBDEFLATE_EXTRA_FLAGS="-DLIBDEFLATE_BUILD_STATIC_LIB=ON -DLIBDEFLATE_BUILD_SHARED_LIB=OFF"
	else
		local CMAKE_LIBDEFLATE_EXTRA_FLAGS="-DLIBDEFLATE_BUILD_STATIC_LIB=OFF -DLIBDEFLATE_BUILD_SHARED_LIB=ON"
	fi

	if cant_use_cache "$libdeflate_dir"; then
		rm -rf "$libdeflate_dir"
		write_download
		download_github_src "ebiggers/libdeflate" "$LIBDEFLATE_VERSION" "libdeflate" | tar -zx >> "$DIR/install.log" 2>&1
		cd "$libdeflate_dir"
		write_configure
		cmake . \
			-DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
			-DCMAKE_PREFIX_PATH="$INSTALL_DIR" \
			-DCMAKE_INSTALL_LIBDIR=lib \
			-DLIBDEFLATE_BUILD_GZIP=OFF \
			$CMAKE_LIBDEFLATE_EXTRA_FLAGS >> "$DIR/install.log" 2>&1
		write_compile
		make -j $THREADS >> "$DIR/install.log" 2>&1 && mark_cache
	else
		write_caching
		cd "$libdeflate_dir"
	fi
	write_install
	make install >> "$DIR/install.log" 2>&1
	cd ..
	write_done
}

cd "$LIB_BUILD_DIR"

build_zlib
build_gmp
build_openssl
build_curl
build_yaml
build_leveldb
if [ "$COMPILE_GD" == "yes" ]; then
	build_libpng
	build_libjpeg
	HAS_GD="--enable-gd"
	HAS_LIBJPEG="--with-jpeg"
else
	HAS_GD=""
	HAS_LIBJPEG=""
fi

build_libxml2
build_libzip
build_sqlite3
build_libdeflate

function get_extension_tar_gz {
	echo -n "  $1: downloading $2..."
	download_file "$3" "php-ext-$1" | tar -zx >> "$DIR/install.log" 2>&1
	mv "$4" "$BUILD_DIR/php/ext/$1"
	write_done
}

function get_github_extension {
	get_extension_tar_gz "$1" "$2" "https://github.com/$3/$4/archive/$5$2.tar.gz" "$4-$2"
}

function get_pecl_extension {
	get_extension_tar_gz "$1" "$2" "https://pecl.php.net/get/$1-$2.tgz" "$1-$2"
}

cd "$BUILD_DIR/php"
write_out "PHP" "Downloading extensions for PocketMine-MP 5..."

get_github_extension "pmmpthread" "$EXT_PMMPTHREAD_VERSION" "pmmp" "ext-pmmpthread"
THREAD_EXT_FLAGS="--enable-pmmpthread"

get_github_extension "yaml" "$EXT_YAML_VERSION" "php" "pecl-file_formats-yaml"

get_github_extension "igbinary" "$EXT_IGBINARY_VERSION" "igbinary" "igbinary"

get_github_extension "recursionguard" "$EXT_RECURSIONGUARD_VERSION" "pmmp" "ext-recursionguard"

echo -n "  crypto: downloading $EXT_CRYPTO_VERSION..."
git clone https://github.com/bukka/php-crypto.git "$BUILD_DIR/php/ext/crypto" >> "$DIR/install.log" 2>&1
cd "$BUILD_DIR/php/ext/crypto"
git checkout "$EXT_CRYPTO_VERSION" >> "$DIR/install.log" 2>&1
git submodule update --init --recursive >> "$DIR/install.log" 2>&1
cd "$BUILD_DIR"
write_done

get_github_extension "leveldb" "$EXT_LEVELDB_VERSION" "pmmp" "php-leveldb"

get_github_extension "chunkutils2" "$EXT_CHUNKUTILS2_VERSION" "pmmp" "ext-chunkutils2"

get_github_extension "libdeflate" "$EXT_LIBDEFLATE_VERSION" "pmmp" "ext-libdeflate"

get_github_extension "morton" "$EXT_MORTON_VERSION" "pmmp" "ext-morton"

get_github_extension "xxhash" "$EXT_XXHASH_VERSION" "pmmp" "ext-xxhash"

get_github_extension "arraydebug" "$EXT_ARRAYDEBUG_VERSION" "pmmp" "ext-arraydebug"

get_github_extension "encoding" "$EXT_ENCODING_VERSION" "pmmp" "ext-encoding"

write_library "PHP" "$PHP_VERSION"

write_configure
cd php
rm -f ./aclocal.m4 >> "$DIR/install.log" 2>&1
rm -rf ./autom4te.cache/ >> "$DIR/install.log" 2>&1
rm -f ./configure >> "$DIR/install.log" 2>&1

./buildconf --force >> "$DIR/install.log" 2>&1

if [ "$DO_STATIC" == "yes" ]; then
	if [ -z "$PKG_CONFIG" ]; then
		PKG_CONFIG="$(which pkg-config)" || true
	fi
	if [ ! -z "$PKG_CONFIG" ]; then
		echo '#!/bin/sh' > "$BUILD_DIR/pkg-config-wrapper"
		echo 'exec '$PKG_CONFIG' "$@" --static' >> "$BUILD_DIR/pkg-config-wrapper"
		chmod +x "$BUILD_DIR/pkg-config-wrapper"
		export PKG_CONFIG="$BUILD_DIR/pkg-config-wrapper"
	fi
fi

export LIBS="$LIBS -ldl"
HAVE_PCNTL="--enable-pcntl"

if [[ "$COMPILE_DEBUG" == "yes" ]]; then
	HAS_DEBUG="--enable-debug"
else
	HAS_DEBUG="--disable-debug"
fi

if [ "$FSANITIZE_OPTIONS" != "" ]; then
	CFLAGS="$CFLAGS -fsanitize=$FSANITIZE_OPTIONS -fno-omit-frame-pointer"
	CXXFLAGS="$CXXFLAGS -fsanitize=$FSANITIZE_OPTIONS -fno-omit-frame-pointer"
	LDFLAGS="-fsanitize=$FSANITIZE_OPTIONS $LDFLAGS"
fi

RANLIB=$RANLIB CFLAGS="$CFLAGS $FLAGS_LTO" CXXFLAGS="$CXXFLAGS $FLAGS_LTO" LDFLAGS="$LDFLAGS $FLAGS_LTO" ./configure $PHP_OPTIMIZATION --prefix="$INSTALL_DIR" \
--exec-prefix="$INSTALL_DIR" \
--with-curl \
--with-zlib \
--with-gmp \
--with-yaml \
--with-openssl \
--with-zip \
--with-libdeflate \
$HAS_LIBJPEG \
$HAS_GD \
--with-leveldb="$INSTALL_DIR" \
--without-readline \
$HAS_DEBUG \
--enable-chunkutils2 \
--enable-morton \
--enable-mbstring \
--disable-mbregex \
--enable-calendar \
$THREAD_EXT_FLAGS \
--enable-fileinfo \
--with-libxml \
--enable-xml \
--enable-dom \
--enable-simplexml \
--enable-xmlreader \
--enable-xmlwriter \
--disable-cgi \
--disable-phpdbg \
--disable-session \
--without-pear \
--without-iconv \
--with-pdo-sqlite \
--with-pdo-mysql \
--with-pic \
--enable-phar \
--enable-ctype \
--enable-sockets \
--enable-shared=no \
--enable-static=yes \
--enable-shmop \
--enable-zts \
--disable-short-tags \
$HAVE_PCNTL \
$HAVE_MYSQLI \
--enable-bcmath \
--enable-cli \
--enable-ftp \
--enable-opcache=$HAVE_OPCACHE \
--enable-opcache-jit=$HAVE_OPCACHE_JIT \
--enable-igbinary \
--with-crypto \
--enable-recursionguard \
--enable-xxhash \
--enable-arraydebug \
--enable-encoding \
$HAVE_VALGRIND \
$CONFIGURE_FLAGS >> "$DIR/install.log" 2>&1

write_compile
sed -i=".backup" 's/PHP_BINARIES. pharcmd$/PHP_BINARIES)/g' Makefile
sed -i=".backup" 's/install-programs install-pharcmd$/install-programs/g' Makefile

if [[ "$DO_STATIC" == "yes" ]]; then
	sed -i=".backup" 's/--mode=link $(CC)/--mode=link $(CXX)/g' Makefile
fi

make -j $THREADS >> "$DIR/install.log" 2>&1
write_install
make install >> "$DIR/install.log" 2>&1

write_status "generating php.ini"
trap - DEBUG
TIMEZONE=$(date +%Z)
echo "memory_limit=1024M" >> "$INSTALL_DIR/bin/php.ini"
echo "date.timezone=$TIMEZONE" >> "$INSTALL_DIR/bin/php.ini"
echo "short_open_tag=0" >> "$INSTALL_DIR/bin/php.ini"
echo "asp_tags=0" >> "$INSTALL_DIR/bin/php.ini"
echo "phar.require_hash=1" >> "$INSTALL_DIR/bin/php.ini"
echo "igbinary.compact_strings=0" >> "$INSTALL_DIR/bin/php.ini"
if [[ "$COMPILE_DEBUG" == "yes" ]]; then
	echo "zend.assertions=1" >> "$INSTALL_DIR/bin/php.ini"
else
	echo "zend.assertions=-1" >> "$INSTALL_DIR/bin/php.ini"
fi
echo "error_reporting=-1" >> "$INSTALL_DIR/bin/php.ini"
echo "display_errors=1" >> "$INSTALL_DIR/bin/php.ini"
echo "display_startup_errors=1" >> "$INSTALL_DIR/bin/php.ini"
echo "recursionguard.enabled=0 ;disabled due to minor performance impact, only enable this if you need it for debugging" >> "$INSTALL_DIR/bin/php.ini"

if [ "$HAVE_OPCACHE" == "yes" ]; then
	echo "zend_extension=opcache.so" >> "$INSTALL_DIR/bin/php.ini"
	echo "opcache.enable=1" >> "$INSTALL_DIR/bin/php.ini"
	echo "opcache.enable_cli=1" >> "$INSTALL_DIR/bin/php.ini"
	echo "opcache.save_comments=1" >> "$INSTALL_DIR/bin/php.ini"
	echo "opcache.validate_timestamps=1" >> "$INSTALL_DIR/bin/php.ini"
	echo "opcache.revalidate_freq=0" >> "$INSTALL_DIR/bin/php.ini"
	echo "opcache.file_update_protection=0" >> "$INSTALL_DIR/bin/php.ini"
	echo "opcache.optimization_level=0x7FFEBFFF" >> "$INSTALL_DIR/bin/php.ini"
	if [ "$HAVE_OPCACHE_JIT" == "yes" ]; then
		echo "" >> "$INSTALL_DIR/bin/php.ini"
		echo "; ---- ! WARNING ! ----" >> "$INSTALL_DIR/bin/php.ini"
		echo "; JIT can provide big performance improvements, but as of PHP $PHP_VERSION it is still unstable. For this reason, it is disabled by default." >> "$INSTALL_DIR/bin/php.ini"
		echo "; Enable it at your own risk. See https://www.php.net/manual/en/opcache.configuration.php#ini.opcache.jit for possible options." >> "$INSTALL_DIR/bin/php.ini"
		echo "opcache.jit=off" >> "$INSTALL_DIR/bin/php.ini"
		echo "opcache.jit_buffer_size=128M" >> "$INSTALL_DIR/bin/php.ini"
	fi
fi

write_done

if [[ "$HAVE_XDEBUG" == "yes" ]]; then
	get_github_extension "xdebug" "$EXT_XDEBUG_VERSION" "xdebug" "xdebug"
	write_library "xdebug" "$EXT_XDEBUG_VERSION"
	cd "$BUILD_DIR/php/ext/xdebug"
	write_configure
	"$INSTALL_DIR/bin/phpize" >> "$DIR/install.log" 2>&1
	./configure --with-php-config="$INSTALL_DIR/bin/php-config" >> "$DIR/install.log" 2>&1
	write_compile
	make -j4 >> "$DIR/install.log" 2>&1
	write_install
	make install >> "$DIR/install.log" 2>&1
	echo "" >> "$INSTALL_DIR/bin/php.ini" 2>&1
	echo ";WARNING: When loaded, xdebug 3.2.0 will cause segfaults whenever an uncaught error is thrown, even if xdebug.mode=off. Load it at your own risk." >> "$INSTALL_DIR/bin/php.ini" 2>&1
	echo ";zend_extension=xdebug.so" >> "$INSTALL_DIR/bin/php.ini" 2>&1
	echo ";https://xdebug.org/docs/all_settings#mode" >> "$INSTALL_DIR/bin/php.ini" 2>&1
	echo "xdebug.mode=off" >> "$INSTALL_DIR/bin/php.ini" 2>&1
	echo "xdebug.start_with_request=yes" >> "$INSTALL_DIR/bin/php.ini" 2>&1
	echo ";The following overrides allow profiler, gc stats and traces to work correctly in ZTS" >> "$INSTALL_DIR/bin/php.ini" 2>&1
	echo "xdebug.profiler_output_name=cachegrind.%s.%p.%r" >> "$INSTALL_DIR/bin/php.ini" 2>&1
	echo "xdebug.gc_stats_output_name=gcstats.%s.%p.%r" >> "$INSTALL_DIR/bin/php.ini" 2>&1
	echo "xdebug.trace_output_name=trace.%s.%p.%r" >> "$INSTALL_DIR/bin/php.ini" 2>&1
	write_done
	write_out INFO "Xdebug is included, but disabled by default. To enable it, change 'xdebug.mode' in your php.ini file."
fi

function separate_symbols {
	local libname="$1"
	local output_dirname

	output_dirname="$SYMBOLS_DIR/$(dirname $libname)"
	mkdir -p "$output_dirname" >> "$DIR/install.log" 2>&1
	cp "$libname" "$SYMBOLS_DIR/$libname.debug" >> "$DIR/install.log" 2>&1
	strip -S "$libname" >> "$DIR/install.log" 2>&1 || rm "$SYMBOLS_DIR/$libname.debug"
}

if [ "$SEPARATE_SYMBOLS" != "no" ]; then
	echo -n "[INFO] Separating debugging symbols into $SYMBOLS_DIR..."
	cd "$INSTALL_DIR"
	find "lib" \( -name '*.so' -o -name '*.so.*' \) -print0 | while IFS= read -r -d '' file; do
		separate_symbols "$file"
	done
	for file in "bin/"*; do
		separate_symbols "$file"
	done
	cd "$DIR"
	write_done
fi

cd "$DIR"
if [ "$DO_CLEANUP" == "yes" ]; then
	write_out "INFO" "Cleaning up"
	rm -r -f "$BUILD_DIR" >> "$DIR/install.log" 2>&1
	rm -f "$INSTALL_DIR/bin/curl"* >> "$DIR/install.log" 2>&1
	rm -f "$INSTALL_DIR/bin/curl-config"* >> "$DIR/install.log" 2>&1
	rm -f "$INSTALL_DIR/bin/c_rehash"* >> "$DIR/install.log" 2>&1
	rm -f "$INSTALL_DIR/bin/openssl"* >> "$DIR/install.log" 2>&1
	rm -r -f "$INSTALL_DIR/man" >> "$DIR/install.log" 2>&1
	rm -r -f "$INSTALL_DIR/share/man" >> "$DIR/install.log" 2>&1
	rm -r -f "$INSTALL_DIR/php" >> "$DIR/install.log" 2>&1
	rm -r -f "$INSTALL_DIR/misc" >> "$DIR/install.log" 2>&1
	rm -r -f "$INSTALL_DIR/lib/"*.a >> "$DIR/install.log" 2>&1
	rm -r -f "$INSTALL_DIR/lib/"*.la >> "$DIR/install.log" 2>&1
	rm -r -f "$INSTALL_DIR/include" >> "$DIR/install.log" 2>&1
fi

date >> "$DIR/install.log" 2>&1
write_out "PocketMine-MP 5" "PHP compilation completed!"
write_out "PocketMine-MP 5" "You should start the server now using \"./start.sh\"."
write_out "PocketMine-MP 5" "If it doesn't work, please send the \"install.log\" file to the Bug Tracker."

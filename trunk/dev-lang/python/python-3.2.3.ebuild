# Copyright 1999-2012 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: /var/cvsroot/gentoo-x86/dev-lang/python/python-3.2.3.ebuild,v 1.16 2012/08/03 21:22:53 blueness Exp $

EAPI="5-hdepend"
WANT_AUTOMAKE="none"
WANT_LIBTOOL="none"

inherit autotools eutils flag-o-matic multilib pax-utils python toolchain-funcs

MY_P="Python-${PV}"
PATCHSET_REVISION="0"

DESCRIPTION="Python is an interpreted, interactive, object-oriented programming language."
HOMEPAGE="http://www.python.org/"
SRC_URI="http://www.python.org/ftp/python/${PV}/${MY_P}.tar.xz
	mirror://gentoo/python-gentoo-patches-${PV}-${PATCHSET_REVISION}.tar.bz2"

LICENSE="PSF-2"
SLOT="3.2"
PYTHON_ABI="${SLOT}"
KEYWORDS="~alpha amd64 arm ~hppa ~ia64 ~m68k ~mips ppc ppc64 ~s390 ~sh ~sparc x86 ~amd64-fbsd ~sparc-fbsd ~x86-fbsd"
IUSE="build doc elibc_uclibc examples gdbm ipv6 +ncurses +readline sqlite +ssl +threads targetroot tk +wide-unicode wininst +xml"

RDEPEND="app-arch/bzip2
		>=sys-libs/zlib-1.1.3
		virtual/libffi
		virtual/libintl
		!build? (
			gdbm? ( sys-libs/gdbm[berkdb] )
			ncurses? (
				>=sys-libs/ncurses-5.2
				readline? ( >=sys-libs/readline-4.1 )
			)
			sqlite? ( >=dev-db/sqlite-3.3.8:3[extensions] )
			ssl? ( dev-libs/openssl )
			tk? (
				>=dev-lang/tk-8.0
				dev-tcltk/blt
			)
			xml? ( >=dev-libs/expat-2.1 )
		)"
DEPEND="${RDEPEND}"
HDEPEND="
		virtual/pkgconfig
		sys-apps/paxctl
		>=sys-devel/autoconf-2.65
		!sys-devel/gcc[libffi]
		targetroot? ( ~${CATEGORY}/${P} )"
RDEPEND+=" !build? ( app-misc/mime-types )
	doc? ( dev-python/python-docs:${SLOT} )"

S="${WORKDIR}/${MY_P}"

pkg_setup() {
	python_pkg_setup

	if [[ "${PV}" =~ ^3\.2(\.[1234])?(_pre)? ]]; then
		rm -f "${EROOT}usr/$(get_libdir)/llibpython3.so"
	else
		die "Deprecated code not deleted"
	fi
}

src_prepare() {
	# Ensure that internal copies of expat, libffi and zlib are not used.
	rm -fr Modules/expat
	rm -fr Modules/_ctypes/libffi*
	rm -fr Modules/zlib

	local excluded_patches
	if ! tc-is-cross-compiler; then
		excluded_patches="*_all_crosscompile.patch"
	fi

	EPATCH_EXCLUDE="${excluded_patches}" EPATCH_SUFFIX="patch" \
		epatch "${WORKDIR}/${PV}-${PATCHSET_REVISION}"
	epatch "${FILESDIR}"/${PN}-3.2.3-x32.patch

	if tc-is-cross-compiler; then
		# Patch contains three fixes:
		# 1. setup.py does not append "-I/usr/include" to the CFLAGS when
		# compiling the python modules for the target system.  Otherwise the
		# compilation can fail, e.g. with weird asm errors, due to wrong system
		# headers being used.  It does not suffice to have the correct
		# "-I${SYSROOT}/usr/include" in the CFLAGS variable in make.conf as the
		# gcc include directory search order will always look in those
		# directories last.
		# 2. Use hostpython and header files from ${SYSROOT} for regen
		# 3. Makefile uses hostpython for compileall
		epatch "${FILESDIR}"/fix-cross-compile.patch
	fi

	# Patch makes setup.py and distutils read the PYTHON_SETUP_SYSROOT
	# variable to look for libraries and headers in the target system
	# and not on the host. Without this it can find libraries on the
	# host which don't exist in the target and fail to link.
	# Example: if ncurses is built without unicode support, linking fails
	# because libncursesw is missing, but present on host.
	# NOTE: the host python must be compiled with this!
	epatch "${FILESDIR}"/python-3.2-sysroot.patch

	if tc-is-cross-compiler; then
		# Make sure above patch was applied to host python.
		local command='from distutils import unixccompiler; unixccompiler.supports_sysroot()'
		if ! /usr/bin/python${SLOT} -c "${command}"; then
			die "Sysroot patch not applied to host Python, reinstall it from this ebuild!"
		fi
	fi

	sed -i -e "s:@@GENTOO_LIBDIR@@:$(get_libdir):g" \
		Lib/distutils/command/install.py \
		Lib/distutils/sysconfig.py \
		Lib/site.py \
		Lib/sysconfig.py \
		Lib/test/test_site.py \
		Makefile.pre.in \
		Modules/Setup.dist \
		Modules/getpath.c \
		setup.py || die "sed failed to replace @@GENTOO_LIBDIR@@"

	# Disable ABI flags.
	sed -e "s/ABIFLAGS=\"\${ABIFLAGS}.*\"/:/" -i configure.in || die "sed failed"

	eautoconf
	eautoheader
}

src_configure() {
	if use build; then
		# Disable extraneous modules with extra dependencies.
		export PYTHON_DISABLE_MODULES="gdbm _curses _curses_panel readline _sqlite3 _tkinter _elementtree pyexpat"
		export PYTHON_DISABLE_SSL="1"
	else
		local disable
		use gdbm     || disable+=" gdbm"
		use ncurses  || disable+=" _curses _curses_panel"
		use readline || disable+=" readline"
		use sqlite   || disable+=" _sqlite3"
		use ssl      || export PYTHON_DISABLE_SSL="1"
		use tk       || disable+=" _tkinter"
		use xml      || disable+=" _elementtree pyexpat" # _elementtree uses pyexpat.
		export PYTHON_DISABLE_MODULES="${disable}"

		if ! use xml; then
			ewarn "You have configured Python without XML support."
			ewarn "This is NOT a recommended configuration as you"
			ewarn "may face problems parsing any XML documents."
		fi
	fi

	if [[ -n "${PYTHON_DISABLE_MODULES}" ]]; then
		einfo "Disabled modules: ${PYTHON_DISABLE_MODULES}"
	fi

	if [[ "$(gcc-major-version)" -ge 4 ]]; then
		append-flags -fwrapv
	fi

	filter-flags -malign-double

	[[ "${ARCH}" == "alpha" ]] && append-flags -fPIC

	# https://bugs.gentoo.org/show_bug.cgi?id=50309
	if is-flagq -O3; then
		is-flagq -fstack-protector-all && replace-flags -O3 -O2
		use hardened && replace-flags -O3 -O2
	fi

	if tc-is-cross-compiler; then
		# configure build python
		OPT="-O1" CFLAGS="${HOST_CFLAGS}" LDFLAGS="${HOST_LDFLAGS}" CC="${HOSTCC}" LD="${HOSTLD}" \
		./configure --{build,host}=${CBUILD} || die "failed to configure build python"

		# build just the parser generator
		OPT="-O1" CFLAGS="${HOST_CFLAGS}" LDFLAGS="${HOST_LDFLAGS}" CC="${HOSTCC}" LD="${HOSTLD}" \
		emake Parser/pgen || die "failed to make parser generator"

		# rename pgen so it isn't overwritten by cross build
		mv Parser/pgen Parser/hostpgen

		# make cross build use the parser generator we have built
		sed -i \
			-e "/^HOSTPYTHON/s:=.*:=./hostpython:" \
			-e "/^HOSTPGEN/s:=.*:=./Parser/hostpgen:" \
			Makefile.pre.in || die "sed failed"

		# make it use the python from the build system
		ln -s /usr/bin/python${SLOT} hostpython

		# clean up
		make distclean
		rm -rf build
	fi

	# Export CXX so it ends up in /usr/lib/python3.X/config/Makefile.
	tc-export CXX
	# The configure script fails to use pkg-config correctly.
	# http://bugs.python.org/issue15506
	export ac_cv_path_PKG_CONFIG=$(tc-getPKG_CONFIG)

	# Set LDFLAGS so we link modules with -lpython3.2 correctly.
	# Needed on FreeBSD unless Python 3.2 is already installed.
	# Please query BSD team before removing this!
	append-ldflags "-L."

	local dbmliborder
	if use gdbm; then
		dbmliborder+="${dbmliborder:+:}gdbm"
	fi

	OPT="" econf \
		--with-fpectl \
		--enable-shared \
		$(use_enable ipv6) \
		$(use_with threads) \
		$(use_with wide-unicode) \
		--infodir='${prefix}/share/info' \
		--mandir='${prefix}/share/man' \
		--with-computed-gotos \
		--with-dbmliborder="${dbmliborder}" \
		--with-libc="" \
		--enable-loadable-sqlite-extensions \
		--with-system-expat \
		--with-system-ffi
}

src_compile() {
	PYTHON_SETUP_SYSROOT="$ROOT" emake CPPFLAGS="" CFLAGS="" LDFLAGS="" || die "emake failed"

	pax-mark m python
}

src_test() {
	# Tests will not work when cross compiling.
	if tc-is-cross-compiler; then
		elog "Disabling tests due to crosscompiling."
		return
	fi

	# Byte compiling should be enabled here.
	# Otherwise test_import fails.
	python_enable_pyc

	# Skip failing tests.
	local skipped_tests="gdb"

	for test in ${skipped_tests}; do
		mv Lib/test/test_${test}.py "${T}"
	done

	# Rerun failed tests in verbose mode (regrtest -w).
	emake test EXTRATESTOPTS="-w" CPPFLAGS="" CFLAGS="" LDFLAGS="" < /dev/tty
	local result="$?"

	for test in ${skipped_tests}; do
		mv "${T}/test_${test}.py" Lib/test
	done

	elog "The following tests have been skipped:"
	for test in ${skipped_tests}; do
		elog "test_${test}.py"
	done

	elog "If you would like to run them, you may:"
	elog "cd '${EPREFIX}$(python_get_libdir)/test'"
	elog "and run the tests separately."

	python_disable_pyc

	if [[ "${result}" -ne 0 ]]; then
		die "emake test failed"
	fi
}

src_install() {
	PYTHON_SETUP_SYSROOT="$ROOT" emake DESTDIR="${D}" altinstall || die "emake altinstall failed"
	python_clean_installation_image -q

	sed \
		-e "s/\(CONFIGURE_LDFLAGS=\).*/\1/" \
		-e "s/\(PY_LDFLAGS=\).*/\1/" \
		-i "${ED}$(python_get_libdir)/config-${SLOT}/Makefile" || die "sed failed"

	mv "${ED}usr/bin/python${SLOT}-config" "${ED}usr/bin/python-config-${SLOT}"

	# Fix collisions between different slots of Python.
	rm -f "${ED}usr/$(get_libdir)/libpython3.so"

	if use build; then
		rm -fr "${ED}usr/bin/idle${SLOT}" "${ED}$(python_get_libdir)/"{idlelib,sqlite3,test,tkinter}
	else
		use elibc_uclibc && rm -fr "${ED}$(python_get_libdir)/test"
		use sqlite || rm -fr "${ED}$(python_get_libdir)/"{sqlite3,test/test_sqlite*}
		use tk || rm -fr "${ED}usr/bin/idle${SLOT}" "${ED}$(python_get_libdir)/"{idlelib,tkinter,test/test_tk*}
	fi

	use threads || rm -fr "${ED}$(python_get_libdir)/multiprocessing"
	use wininst || rm -f "${ED}$(python_get_libdir)/distutils/command/"wininst-*.exe

	dodoc Misc/{ACKS,HISTORY,NEWS} || die "dodoc failed"

	if use examples; then
		insinto /usr/share/doc/${PF}/examples
		find Tools -name __pycache__ -print0 | xargs -0 rm -fr
		doins -r Tools || die "doins failed"
	fi

	newconfd "${FILESDIR}/pydoc.conf" pydoc-${SLOT} || die "newconfd failed"
	newinitd "${FILESDIR}/pydoc.init" pydoc-${SLOT} || die "newinitd failed"
	sed \
		-e "s:@PYDOC_PORT_VARIABLE@:PYDOC${SLOT/./_}_PORT:" \
		-e "s:@PYDOC@:pydoc${SLOT}:" \
		-i "${ED}etc/conf.d/pydoc-${SLOT}" "${ED}etc/init.d/pydoc-${SLOT}" || die "sed failed"
}

pkg_preinst() {
	if has_version "<${CATEGORY}/${PN}-${SLOT}" && ! has_version ">=${CATEGORY}/${PN}-${SLOT}_alpha"; then
		python_updater_warning="1"
	fi
}

eselect_python_update() {
	if [[ -z "$(eselect python show)" || ! -f "${EROOT}usr/bin/$(eselect python show)" ]]; then
		eselect python update
	fi

	if [[ -z "$(eselect python show --python${PV%%.*})" || ! -f "${EROOT}usr/bin/$(eselect python show --python${PV%%.*})" ]]; then
		eselect python update --python${PV%%.*}
	fi
}

pkg_postinst() {
	eselect_python_update

	python_mod_optimize -f -x "/(site-packages|test|tests)/" $(python_get_libdir)

	if [[ "${python_updater_warning}" == "1" ]]; then
		ewarn "You have just upgraded from an older version of Python."
		ewarn "You should switch active version of Python ${PV%%.*} and run"
		ewarn "'python-updater [options]' to rebuild Python modules."
	fi
}

pkg_postrm() {
	eselect_python_update

	python_mod_cleanup $(python_get_libdir)
}

# Copyright 1999-2013 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: /var/cvsroot/gentoo-x86/sys-devel/llvm/llvm-3.2.ebuild,v 1.3 2013/01/07 20:22:12 voyageur Exp $

EAPI=5

inherit autotools eutils flag-o-matic multilib toolchain-funcs pax-utils python-convert

DESCRIPTION="Low Level Virtual Machine"
HOMEPAGE="http://llvm.org/"
SRC_URI="http://llvm.org/releases/${PV}/${P}.src.tar.gz"

LICENSE="UoI-NCSA"
SLOT="0"
KEYWORDS="~amd64 ~arm ~ppc ~x86 ~amd64-fbsd ~x86-fbsd ~x64-freebsd ~amd64-linux ~x86-linux ~ppc-macos ~x64-macos"
IUSE="debug doc gold +libffi minimal multitarget ocaml test udis86 vim-syntax"

DEPEND="dev-lang/perl
	|| ( dev-lang/python:2.5 dev-lang/python:2.6 dev-lang/python:2.7 )
	dev-python/sphinx
	>=sys-devel/make-3.79
	>=sys-devel/flex-2.5.4
	>=sys-devel/bison-1.875d
	|| ( >=sys-devel/gcc-3.0 >=sys-devel/gcc-apple-4.2.1 )
	|| ( >=sys-devel/binutils-2.18 >=sys-devel/binutils-apple-3.2.3 )
	gold? ( >=sys-devel/binutils-2.22[cxx] )
	libffi? ( virtual/pkgconfig
		virtual/libffi )
	ocaml? ( dev-lang/ocaml )
	udis86? ( dev-libs/udis86[pic(+)] )"
RDEPEND="!minimal? ( dev-lang/perl )
	libffi? ( virtual/libffi )
	vim-syntax? ( || ( app-editors/vim app-editors/gvim ) )"

S=${WORKDIR}/${P}.src

pkg_setup() {
	# need to check if the active compiler is ok

	broken_gcc=" 3.2.2 3.2.3 3.3.2 4.1.1 "
	broken_gcc_x86=" 3.4.0 3.4.2 "
	broken_gcc_amd64=" 3.4.6 "

	gcc_vers=$(gcc-fullversion)

	if [[ ${broken_gcc} == *" ${version} "* ]] ; then
		elog "Your version of gcc is known to miscompile llvm."
		elog "Check http://www.llvm.org/docs/GettingStarted.html for"
		elog "possible solutions."
		die "Your currently active version of gcc is known to miscompile llvm"
	fi

	if [[ ${CHOST} == i*86-* && ${broken_gcc_x86} == *" ${version} "* ]] ; then
		elog "Your version of gcc is known to miscompile llvm on x86"
		elog "architectures.  Check"
		elog "http://www.llvm.org/docs/GettingStarted.html for possible"
		elog "solutions."
		die "Your currently active version of gcc is known to miscompile llvm"
	fi

	if [[ ${CHOST} == x86_64-* && ${broken_gcc_amd64} == *" ${version} "* ]];
	then
		 elog "Your version of gcc is known to miscompile llvm in amd64"
		 elog "architectures.  Check"
		 elog "http://www.llvm.org/docs/GettingStarted.html for possible"
		 elog "solutions."
		die "Your currently active version of gcc is known to miscompile llvm"
	 fi
}

src_prepare() {
	# unfortunately ./configure won't listen to --mandir and the-like, so take
	# care of this.
	einfo "Fixing install dirs"
	sed -e 's,^PROJ_docsdir.*,PROJ_docsdir := $(PROJ_prefix)/share/doc/'${PF}, \
		-e 's,^PROJ_etcdir.*,PROJ_etcdir := '"${EPREFIX}"'/etc/llvm,' \
		-e 's,^PROJ_libdir.*,PROJ_libdir := $(PROJ_prefix)/'$(get_libdir)/${PN}, \
		-i Makefile.config.in || die "Makefile.config sed failed"
	sed -e "/ActiveLibDir = ActivePrefix/s/lib/$(get_libdir)\/${PN}/" \
		-i tools/llvm-config/llvm-config.cpp || die "llvm-config sed failed"

	einfo "Fixing rpath and CFLAGS"
	sed -e 's,\$(RPATH) -Wl\,\$(\(ToolDir\|LibDir\)),$(RPATH) -Wl\,'"${EPREFIX}"/usr/$(get_libdir)/${PN}, \
		-e '/OmitFramePointer/s/-fomit-frame-pointer//' \
		-i Makefile.rules || die "rpath sed failed"
	if use gold; then
		sed -e 's,\$(SharedLibDir),'"${EPREFIX}"/usr/$(get_libdir)/${PN}, \
			-i tools/gold/Makefile || die "gold rpath sed failed"
	fi

	# FileCheck is needed at least for dragonegg tests
	sed -e "/NO_INSTALL = 1/s/^/#/" -i utils/FileCheck/Makefile \
		|| die "FileCheck Makefile sed failed"

	# Specify python version
	python-convert_convert_shebangs -r /usr/bin/python2 test/Scripts

	epatch "${FILESDIR}"/${PN}-3.2-nodoctargz.patch
	epatch "${FILESDIR}"/${PN}-3.0-PPC_macro.patch
	epatch "${FILESDIR}"/llvm-3.2-cross-compile.patch

	# User patches
	epatch_user

	# Regenerate autotools (from autoconf/AutoRegen.sh).
	pushd autoconf >/dev/null || die
	local outfile=configure
	local configfile=configure.ac
	local cwd=`pwd`
	eaclocal --force -I "${cwd}/m4" || die "aclocal failed"
	eautoconf --force --warnings=all -o "../${outfile}" "${configfile}" || die "autoconf failed"
	popd >/dev/null || die
	autotools_run_tool autoheader --warnings=all -I autoconf -I autoconf/m4 "autoconf/${configfile}" || die "autoheader failed"

	# Regenerate autotools in sample (from projects/sample/autoconf/AutoRegen.sh).
	pushd projects/sample/autoconf >/dev/null || die
	local cwd=`pwd`
	eaclocal -I "${cwd}/m4" || die "aclocal failed"
	eautoconf --warnings=all -o ../configure configure.ac || die "autoconf failed"
	popd >/dev/null || die
}

src_configure() {
	local CONF_FLAGS="--enable-shared
		--with-optimize-option=
		$(use_enable !debug optimized)
		$(use_enable debug assertions)
		$(use_enable debug expensive-checks)"

	if use multitarget; then
		CONF_FLAGS="${CONF_FLAGS} --enable-targets=all"
	else
		CONF_FLAGS="${CONF_FLAGS} --enable-targets=host,cpp"
	fi

	if use amd64; then
		CONF_FLAGS="${CONF_FLAGS} --enable-pic"
	fi

	if use gold; then
		CONF_FLAGS="${CONF_FLAGS} --with-binutils-include=${EPREFIX}/usr/include/"
	fi
	if use ocaml; then
		CONF_FLAGS="${CONF_FLAGS} --enable-bindings=ocaml"
	else
		CONF_FLAGS="${CONF_FLAGS} --enable-bindings=none"
	fi

	if use udis86; then
		CONF_FLAGS="${CONF_FLAGS} --with-udis86"
	fi

	if use libffi; then
		append-cppflags "$(pkg-config --cflags libffi)"
	fi
	CONF_FLAGS="${CONF_FLAGS} $(use_enable libffi)"

	mkdir build || die
	cd build || die

	# llvm prefers clang over gcc, so we may need to force that
	tc-export CC CXX
	ECONF_SOURCE="${S}" econf ${CONF_FLAGS}
}

src_compile() {
	pushd build >/dev/null || die
	emake VERBOSE=1 KEEP_SYMBOLS=1 REQUIRES_RTTI=1
	popd >/dev/null || die

	emake -C docs -f Makefile.sphinx man
	use doc && emake -C docs -f Makefile.sphinx html

	pax-mark m build/Release/bin/lli
	if use test; then
		pax-mark m build/unittests/ExecutionEngine/JIT/Release/JITTests
		pax-mark m build/unittests/ExecutionEngine/MCJIT/Release/MCJITTests
		pax-mark m build/unittests/Support/Release/SupportTests
	fi
}

src_install() {
	pushd build >/dev/null || die
	emake KEEP_SYMBOLS=1 DESTDIR="${D}" install
	popd >/dev/null || die

	doman docs/_build/man/*.1
	use doc && dohtml -r docs/_build/html/

	if use vim-syntax; then
		insinto /usr/share/vim/vimfiles/syntax
		doins utils/vim/*.vim
	fi

	# Fix install_names on Darwin.  The build system is too complicated
	# to just fix this, so we correct it post-install
	local lib= f= odylib= libpv=${PV}
	if [[ ${CHOST} == *-darwin* ]] ; then
		eval $(grep PACKAGE_VERSION= configure)
		[[ -n ${PACKAGE_VERSION} ]] && libpv=${PACKAGE_VERSION}
		for lib in lib{EnhancedDisassembly,LLVM-${libpv},LTO,profile_rt}.dylib {BugpointPasses,LLVMHello}.dylib ; do
			# libEnhancedDisassembly is Darwin10 only, so non-fatal
			[[ -f ${ED}/usr/lib/${PN}/${lib} ]] || continue
			ebegin "fixing install_name of $lib"
			install_name_tool \
				-id "${EPREFIX}"/usr/lib/${PN}/${lib} \
				"${ED}"/usr/lib/${PN}/${lib}
			eend $?
		done
		for f in "${ED}"/usr/bin/* "${ED}"/usr/lib/${PN}/libLTO.dylib ; do
			odylib=$(scanmacho -BF'%n#f' "${f}" | tr ',' '\n' | grep libLLVM-${libpv}.dylib)
			ebegin "fixing install_name reference to ${odylib} of ${f##*/}"
			install_name_tool \
				-change "${odylib}" \
					"${EPREFIX}"/usr/lib/${PN}/libLLVM-${libpv}.dylib \
				"${f}"
			eend $?
		done
	fi
}

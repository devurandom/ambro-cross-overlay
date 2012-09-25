# Copyright 1999-2012 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: /var/cvsroot/gentoo-x86/sys-libs/cracklib/cracklib-2.8.19.ebuild,v 1.10 2012/08/26 17:23:41 armin76 Exp $

EAPI="5-hdepend"
PYTHON_DEPEND="python? 2"
SUPPORT_PYTHON_ABIS="1"
RESTRICT_PYTHON_ABIS="3.* 2.7-pypy-* *-jython"

inherit eutils distutils library-path libtool toolchain-funcs

MY_P=${P/_}
DESCRIPTION="Password Checking Library"
HOMEPAGE="http://sourceforge.net/projects/cracklib"
SRC_URI="mirror://sourceforge/cracklib/${MY_P}.tar.gz"

LICENSE="LGPL-2.1"
SLOT="0"
KEYWORDS="alpha amd64 arm hppa ia64 m68k ~mips ppc ppc64 s390 sh sparc x86 ~x86-fbsd ~x86-interix ~amd64-linux ~ia64-linux ~x86-linux ~ppc-macos ~x86-macos ~m68k-mint"
IUSE="nls python static-libs targetroot zlib"

RDEPEND="zlib? ( sys-libs/zlib )"
DEPEND="${RDEPEND}"
HDEPEND="python? ( dev-python/setuptools )
	 targetroot? ( ~${CATEGORY}/${P} )"

S=${WORKDIR}/${MY_P}

PYTHON_MODNAME="cracklib.py"
do_python() {
	use python || return 0
	case ${EBUILD_PHASE} in
	prepare|configure|compile|install)
		pushd python > /dev/null || die
		distutils_src_${EBUILD_PHASE}
		popd > /dev/null
		;;
	*)
		distutils_pkg_${EBUILD_PHASE}
		;;
	esac
}

pkg_setup() {
	# workaround #195017
	if has unmerge-orphans ${FEATURES} && has_version "<${CATEGORY}/${PN}-2.8.10" ; then
		eerror "Upgrade path is broken with FEATURES=unmerge-orphans"
		eerror "Please run: FEATURES=-unmerge-orphans emerge cracklib"
		die "Please run: FEATURES=-unmerge-orphans emerge cracklib"
	fi

	use python && python_pkg_setup
}

src_prepare() {
	elibtoolize #269003
	do_python
}

src_configure() {
	export ac_cv_header_zlib_h=$(usex zlib)
	export ac_cv_search_gzopen=$(usex zlib -lz no)
	econf \
		--with-default-dict='$(libdir)/cracklib_dict' \
		--without-python \
		$(use_enable nls) \
		$(use_enable static-libs static)
}

src_compile() {
	# https://bugs.gentoo.org/show_bug.cgi?id=167248
	epatch "${FILESDIR}"/${PN}-2.8.19-portable-dictionary.patch

	default
	do_python
}

src_install() {
	emake DESTDIR="${D}" install || die
	use static-libs || find "${ED}"/usr -name libcrack.la -delete
	rm -r "${ED}"/usr/share/cracklib

	do_python

	# move shared libs to /
	gen_usr_ldscript -a crack

	insinto /usr/share/dict
	doins dicts/cracklib-small || die

	# generate dictionary
	if [ "${ROOT}" = / ]; then
		sh "${S}/util/cracklib-format" "${ED}"/usr/share/dict/* \
		| library-path-run "${S}/lib/.libs" "${S}/util/cracklib-packer" cracklib_dict || die
	else
		create-cracklib-dict -o cracklib_dict "${ED}"/usr/share/dict/* || die
	fi
	insinto /usr/$(get_libdir)
	doins cracklib_dict.hwm
	doins cracklib_dict.pwd
	doins cracklib_dict.pwi

	dodoc AUTHORS ChangeLog NEWS README*
}

pkg_postinst() {
	do_python
}

pkg_postrm() {
	do_python
}

# Copyright 1999-2012 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: /var/cvsroot/gentoo-x86/eclass/vcs-snapshot.eclass,v 1.4 2012/06/11 14:22:19 mgorny Exp $

# @ECLASS: vcs-snapshot.eclass
# @MAINTAINER:
# mgorny@gentoo.org
# @BLURB: support eclass for unpacking VCS snapshot tarballs
# @DESCRIPTION:
# This eclass provides a convenience src_unpack() which does unpack all
# the tarballs in SRC_URI to locations matching their (local) names,
# discarding the original parent directory.
#
# The typical use case are VCS snapshots, coming from github, bitbucket
# and similar services. They have hash appended to the directory name
# which makes extracting them a painful experience. But if you just use
# a SRC_URI arrow to rename it (which you're likely have to do anyway),
# vcs-snapshot will just extract it into a matching directory.
#
# Please note that this eclass handles only tarballs (.tar, .tar.gz,
# .tar.bz2 & .tar.xz). For any other file format (or suffix) it will
# fall back to regular unpack. Support for additional formats may be
# added at some point so please keep your SRC_URIs clean.
#
# @EXAMPLE:
#
# @CODE
# EAPI=4
# AUTOTOOLS_AUTORECONF=1
# inherit autotools-utils vcs-snapshot
#
# SRC_URI="http://github.com/example/${PN}/tarball/v${PV} -> ${P}.tar.gz"
# @CODE
#
# and however the tarball was originally named, all files will appear
# in ${WORKDIR}/${P}.

case ${EAPI:-0} in
	0|1|2|3|4|5|5-hdepend) ;;
	*) die "vcs-snapshot.eclass API in EAPI ${EAPI} not yet established."
esac

EXPORT_FUNCTIONS src_unpack

vcs-snapshot_src_unpack() {
	local f

	for f in ${A}
	do
		case "${f}" in
			*.tar|*.tar.gz|*.tar.bz2|*.tar.xz)
				local destdir=${WORKDIR}/${f%.tar*}

				# XXX: check whether the directory structure inside is
				# fine? i.e. if the tarball has actually a parent dir.
				mkdir "${destdir}" || die
				tar -C "${destdir}" -x --strip-components 1 \
					-f "${DISTDIR}/${f}" || die
				;;
			*)
				# fall back to the default method
				unpack "${f}"
				;;
		esac
	done
}

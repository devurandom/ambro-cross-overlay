Here are instructions for cross-compiling an ARM Gentoo root filesystem (ideally equivalent to stage3).

# Install patched packages #

First add this overlay (the SVN repository) to your Gentoo system. E.g. to check it out directly from SVN:

```
cd /usr/local
svn checkout https://ambro-cross-overlay.googlecode.com/svn/trunk/ ambro-cross-overlay
```

Then register it in /etc/portage/make.conf (or /etc/make.conf, whatever you have):

```
PORTDIR_OVERLAY="
<other stuff>
/usr/local/ambro-cross-overlay
"
```

First you have to install Portage version at least 2.1.11.22 or 2.2.0\_alpha133. This is because some ebuilds in this overlay use the experimental [HDEPEND EAPI](http://blogs.gentoo.org/zmedico/2012/09/25/experimental-eapi-5-hdepend/).

```
<sync portage however you do that>
<unmask portage in /etc/portage/package.keywords>
emerge -av1 sys-apps/portage
<MAKE SURE IT'S NEW ENOUGH, SEE ABOVE>
```

Then reinstall the following packages, and make sure you have the following packages installed **from this overlay**:

  * sys-devel/crossdev
  * dev-lang/python

```
emerge -av sys-devel/crossdev::ambro-cross dev-lang/python::ambro-cross
```

# Build a cross toolchain #

If you haven't done so yet, create an overlay for crossdev to put toolchain packages inside.

```
mkdir /usr/local/portage-crossdev
```

Then add it to your make.conf:

```
PORTDIR_OVERLAY="
/usr/local/portage-crossdev
<other stuff>
/usr/local/ambro-cross-overlay
"
```

Now build a cross-compilation toolchain using crossdev. With the architecture choices used here, the result will be able to run on the [Raspberry Pi](http://www.raspberrypi.org/).

```
crossdev --ov-output /usr/local/portage-crossdev --stable armv6j-hardfloat-linux-gnueabi
```

**--ov-output**: crossdev claims it outputs to the last directory in PORTDIR\_OVERLAY, but that is wrong. Hence we specifically instruct it to output into the portage-crossdev directory.

**--stable**: I have only patched stable versions of various packages to cross-compile. In any case, the stable/unstable choice here has to match with what versions of {linux-headers,gcc,glibc} will be installed into the target system.

# Set up the cross prefix #

Choose an empty folder where the target system will be built. **Do not use /usr/CHOST**; we will build a clean system. Create this directory and export it to the environment variable SYSROOT.

```
mkdir /mnt/cross-arm
export SYSROOT=/mnt/cross-arm
```

Now we set up some configuration for Portage.

```
mkdir -p ${SYSROOT}/etc/portage
ln -s /usr/portage/profiles/default/linux/arm/10.0 ${SYSROOT}/etc/make.profile
```

Create ${SYSROOT}/etc/portage/make.conf. Make sure to adjust the overlay path.
```
ACCEPT_KEYWORDS="arm"
ARCH="arm"
CHOST="armv6j-hardfloat-linux-gnueabi"
CFLAGS="-O2 -pipe -march=armv6j -mfpu=vfp -mfloat-abi=hard"
CXXFLAGS="${CFLAGS}"
MAKEOPTS="-j5"
USE="arm symlink"
PORTDIR_OVERLAY="/usr/local/ambro-cross-overlay"
```

If you want to build binary packages for cross-compile packages, create a directory that will hold them and also add this to make.conf:

```
FEATURES="buildpkg"
PKGDIR="/usr/local/arm-pkg"
```

Link package.keywords and package.mask:
```
mkdir -p ${SYSROOT}/etc/portage/package.{keywords,mask,use}
ln -s /usr/local/ambro-cross-overlay/Documentation/package.keywords ${SYSROOT}/etc/portage/package.keywords/ambro-cross
ln -s /usr/local/ambro-cross-overlay/Documentation/package.mask ${SYSROOT}/etc/portage/package.mask/ambro-cross
ln -s /usr/local/ambro-cross-overlay/Documentation/package.use ${SYSROOT}/etc/portage/package.use/ambro-cross
```

# Bootstrap the system #

Install baselayout with the build use flag, in order to create a basic directory structure. Make sure to use my **cross-emerge-ng** emerge wrapper. Later, baselayout will be reinstalled without this flag.

```
USE=build cross-emerge-ng --nodeps -av1 sys-apps/baselayout
```

Now we build a libc into the target. This will use the headers and libraries which came with the cross compiler (in /usr/CHOST).

```
DONT_WRAP_COMPILERS=1 cross-emerge-ng -av1 sys-kernel/linux-headers sys-libs/glibc
```

The DONT\_WRAP\_COMPILERS variable tells cross-emerge-ng not to set CC and CXX to /usr/bin/chost-g{cc,++}. However, from this point on, we will use those wrappers. The only thing they do is prepend "--sysroot ${SYSROOT}" to compiler arguments to make sure they're looking for headers and libraries within SYSROOT, and nowhere else.

Now we install the rest of the system.

```
cross-emerge-ng -av1uN @system
```

NOTE: if sys-apps/acl fails, just run the emerge again and it should work. This is due to a circular dependency that isn't being reported for some reason. The second emerge will probably work because a different installation order will be chosen where everything compiles.

Once everything is installed, the only thing left is to regenerate the linker cache. This is needed because emerge doesn't do it automatically when cross compiling, for some unknown reason. If you forget to do this, programs will fail to start, complaining of missing libraries.

```
ROOT=$SYSROOT eselect env update
```

What you have now in SYSROOT should be pretty close to a stage3 produced by Catalyst - except that this was made completely via cross-compilation and without chrooting.

# Known problems #

User and group accounts are not added by ebuilds. This in particular prevents sshd from starting. To fix it from a booted system or chroot:

```
groupadd -g 22 sshd
useradd -g 22 -u 22 -d /var/empty -s /sbin/nologin sshd
```


---


Udevd may not be started automatically. To fix it, just add the udev service to the boot runlevel:

```
rc-update add udev boot
```


---


Packages using Python 3.2 cannot be build on the target machine (i.e. in the native / non-cross-compiler environment), because Python saves the CC used to build it in `${ROOT}/usr/lib/python3.2/config-3.2/Makefile`. It will point to `${ROOT}/etc/crossdev/gcc`, which obviously does not exist / work properly on the target machine.

# Supported packages #

Other than packages which are pulled in by @system, the following packages are tested regularly:

```
app-admin/syslog-ng
app-misc/tmux
dev-util/strace
dev-vcs/subversion
net-fs/samba
net-misc/badvpn
net-misc/ntp
net-p2p/rtorrent
sys-block/parted
sys-devel/gdb
sys-fs/mtd-utils
sys-process/schedtool
```
#!/bin/bash

DOM0_UPDATES_DIR=/var/lib/qubes/dom0-updates

DOIT=0
GUI=1
CLEAN=0
CHECK_ONLY=0
OPTS="--installroot $DOM0_UPDATES_DIR --config=$DOM0_UPDATES_DIR/etc/yum.conf"
PKGLIST=
export LC_ALL=C

while [ -n "$1" ]; do
    case "$1" in
        --doit)
            DOIT=1
            ;;
        --nogui)
            GUI=0
            ;;
        --gui)
            GUI=1
            ;;
        --clean)
            CLEAN=1
            ;;
        --check-only)
            CHECK_ONLY=1
            ;;
        -*)
            OPTS="$OPTS $1"
            ;;
        *)
            PKGLIST="$PKGLIST $1"
            ;;
    esac
    shift
done

if ! [ -d "$DOM0_UPDATES_DIR" ]; then
    echo "Dom0 updates dir does not exists: $DOM0_UPDATES_DIR" >&2
    exit 1
fi

mkdir -p $DOM0_UPDATES_DIR/etc
sed -i '/^reposdir\s*=/d' $DOM0_UPDATES_DIR/etc/yum.conf

if [ -e /etc/debian_version ]; then
    # Default rpm configuration on Debian uses ~/.rpmdb for rpm database (as
    # rpm isn't native package manager there)
    mkdir -p "$DOM0_UPDATES_DIR$HOME"
    ln -nsf "$DOM0_UPDATES_DIR/var/lib/rpm" "$DOM0_UPDATES_DIR$HOME/.rpmdb"
fi
# Rebuild rpm database in case of different rpm version
rm -f $DOM0_UPDATES_DIR/var/lib/rpm/__*
rpm --root=$DOM0_UPDATES_DIR --rebuilddb

if [ "$CLEAN" = "1" ]; then
    yum $OPTS clean all
    rm -f $DOM0_UPDATES_DIR/packages/*
fi

if [ "x$PKGLIST" = "x" ]; then
    echo "Checking for dom0 updates..." >&2
    UPDATES=`yum $OPTS check-update -q | cut -f 1 -d ' ' | grep -v "^Obsoleting"`
else
    PKGS_FROM_CMDLINE=1
fi

if [ -z "$PKGLIST" -a -z "$UPDATES" ]; then
    echo "No new updates available"
    if [ "$GUI" = 1 ]; then
        zenity --info --text="No new updates available"
    fi
    exit 0
fi

if [ "$CHECK_ONLY" = "1" ]; then
    echo "Available updates: $PKGLIST"
    exit 100
fi

if [ "$DOIT" != "1" -a "$PKGS_FROM_CMDLINE" != "1" ]; then
    zenity --question --title="Qubes Dom0 updates" \
      --text="There are updates for dom0 available, do you want to download them now?" || exit 0
fi

YUM_ACTION=upgrade
if [ "$PKGS_FROM_CMDLINE" == 1 ]; then
    GUI=0
    YUM_ACTION=install
fi

YUM_COMMAND="fakeroot yum $YUM_ACTION -y --downloadonly --downloaddir=$DOM0_UPDATES_DIR/packages"
# check for --downloadonly option - if not supported (Debian), fallback to
# yumdownloader
if ! yum --help | grep -q downloadonly; then
    if [ "$YUM_ACTION" = "upgrade" ]; then
        PKGLIST=$UPDATES
    fi
    YUM_COMMAND="yumdownloader --destdir=$DOM0_UPDATES_DIR/packages --resolve"
fi

mkdir -p "$DOM0_UPDATES_DIR/packages"

set -e

if [ "$GUI" = 1 ]; then
    ( echo "1"
    $YUM_COMMAND $OPTS $PKGLIST
    echo 100 ) | zenity --progress --pulsate --auto-close --auto-kill \
         --text="Downloading updates for Dom0, please wait..." --title="Qubes Dom0 updates"
else
    $YUM_COMMAND $OPTS $PKGLIST
fi

if ls $DOM0_UPDATES_DIR/packages/*.rpm > /dev/null 2>&1; then
    /usr/lib/qubes/qrexec-client-vm dom0 qubes.ReceiveUpdates /usr/lib/qubes/qfile-agent $DOM0_UPDATES_DIR/packages/*.rpm
else
    echo "No packages downloaded"
fi

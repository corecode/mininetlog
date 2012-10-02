#!/bin/sh

NV_DIR=/var/lib/mininetlog
VOLATILE_DIR=/run/mininetlog

not_found() {
        echo "Status: 404 Not Found"
        echo ""
	[ -n "$*" ] && echo "$*"
        exit
}


IFACE=${PATH_INFO#/}

case "$IFACE" in
*/*)
	not_found "$IFACE"
	;;
esac

NV_NAME="$NV_DIR/$IFACE.log.gz"
VOLATILE_NAME="$VOLATILE_DIR/$IFACE.log"

[ ! -e "$NV_NAME" -a ! -e "$VOLATILE_NAME" ] && not_found

echo "Content-type: text/csv"
echo ""

zcat "$NV_NAME"
cat "$VOLATILE_NAME"

exit 0

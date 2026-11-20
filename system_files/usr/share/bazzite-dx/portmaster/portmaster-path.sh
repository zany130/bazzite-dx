#!/bin/sh
# Bazzite-DX optional Portmaster integration; effective on next desktop login.
case ":${XDG_DATA_DIRS:-}:" in
    *:/var/lib/bazzite-dx/portmaster/share:*) ;;
    *) export XDG_DATA_DIRS="/var/lib/bazzite-dx/portmaster/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}" ;;
esac

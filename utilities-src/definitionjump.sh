#!/bin/sh
UNESCAPE="$(dirname "$0")/string.awk"
ITEMS="$(emacsclient -s "$GLISP_EMACSID" -e '(ss-find-definitions "'"${1}"'")'| awk -f "$UNESCAPE" |tr '\n' ' ')"
#printf '%s\n' "$ITEMS"
#printf '%q\n' "$ITEMS"
eval "for item in $ITEMS; do echo \$item; done"

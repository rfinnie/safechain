#!/bin/sh
########################################################################
# Copyright (C) 2013 Canonical Ltd.
# Original author: Ryan Finnie <ryan.finnie@canonical.com>
#
# Usage (assuming a_to_b.sh):
#
# . /etc/network/safechain.sh
# sc_preprocess a_to_b
# sc_add_rule a_to_b -d $ADELIE $SSH -j ACCEPT
# sc_add_rule a_to_b ...
# sc_postprocess a_to_b
#
# You are still responsible for creating "a_to_b" (the "jump chain")
# ahead of time.  When everything goes right, any "sc_add_rule a_to_b"
# rules added will live in the "a_to_b_live" chain, and a jump from
# "a_to_b" to "a_to_b_live" will automatically be maintained.
#
# When run from the terminal, verbose output will be produced.
########################################################################

set -e
set -u

# Only be verbose if stderr is a terminal
if [ -t 2 ]; then
    SC_V=1
else
    SC_V=0
fi

# Set up the environment before adding new rules
sc_preprocess() {
    SC_NAME="$1"
    [ "${SC_V}" = 1 ] && echo "[$(date +'%H:%M:%S')] ${SC_NAME}: Running sanity checks" >&2
    # Check for jump chain (must exist)
    if ! iptables -n -L ${SC_NAME} >/dev/null 2>/dev/null; then
        echo "${SC_NAME} does not exist!  Cowardly refusing to continue." >&2
        echo "Please examine iptables-save and figure out what went wrong." >&2
        exit 1
    fi
    # Create the live chain if it doesn't exist (system boot)
    iptables -N ${SC_NAME}_live 2>/dev/null || true
    # Check for old chain (must not exist)
    if iptables -n -L ${SC_NAME}_old >/dev/null 2>/dev/null; then
        echo "${SC_NAME}_old exists!  Cowardly refusing to continue." >&2
        echo "Please examine iptables-save and figure out what went wrong." >&2
        exit 1
    fi
    # Check for new chain (must not exist)
    if iptables -n -L ${SC_NAME}_new >/dev/null 2>/dev/null; then
        echo "${SC_NAME}_new exists!  Cowardly refusing to continue." >&2
        echo "Please examine iptables-save and figure out what went wrong." >&2
        exit 1
    fi
    [ "${SC_V}" = 1 ] && echo -n "[$(date +'%H:%M:%S')] ${SC_NAME}: Creating and populating new chain" >&2
    iptables -N ${SC_NAME}_new
    SC_ADD_COUNT=0
}

# All the magic needed to move the new rules into place
sc_postprocess() {
    SC_NAME="$1"
    if [ "${SC_V}" = 1 ]; then
        echo " ${SC_ADD_COUNT} rules added." >&2
    fi
    [ "${SC_V}" = 1 ] && echo -n "[$(date +'%H:%M:%S')] ${SC_NAME}: Prepending new jump to jump chain" >&2
    iptables -I ${SC_NAME} -j ${SC_NAME}_new
    [ "${SC_V}" = 1 ] && echo " (new ruleset is now running)" >&2
    [ "${SC_V}" = 1 ] && echo "[$(date +'%H:%M:%S')] ${SC_NAME}: Renaming live chain to old chain" >&2
    # When this happens, the jump to ${SC_NAME}_live in the jump chain
    # is automatically renamed to ${SC_NAME}_old at the same time.
    iptables -E ${SC_NAME}_live ${SC_NAME}_old
    [ "${SC_V}" = 1 ] && echo "[$(date +'%H:%M:%S')] ${SC_NAME}: Renaming new chain to live chain" >&2
    # When this happens, the jump to ${SC_NAME}_new in the jump chain is
    # automatically renamed to ${SC_NAME}_live at the same time.
    iptables -E ${SC_NAME}_new ${SC_NAME}_live
    [ "${SC_V}" = 1 ] && echo "[$(date +'%H:%M:%S')] ${SC_NAME}: Removing old jump from jump chain" >&2
    # As noted above, this used to be a jump to ${SC_NAME}_live, until
    # the rename.  Note that this rule might not exist, e.g. during
    # first boot.
    iptables -D ${SC_NAME} -j ${SC_NAME}_old 2>/dev/null || true
    [ "${SC_V}" = 1 ] && echo "[$(date +'%H:%M:%S')] ${SC_NAME}: Flushing and removing old chain" >&2
    # If everything went well, there should be no more references to
    # this chain, and a flush/delete will succeed.
    iptables -F ${SC_NAME}_old
    iptables -X ${SC_NAME}_old
    [ "${SC_V}" = 1 ] && echo "[$(date +'%H:%M:%S')] ${SC_NAME}: Done!" >&2
}

# Wrapper for "iptables -A", redirecting to the new chain
sc_add_rule() {
    SC_NAME="$1"; shift
    if [ -n "${SC_COMMENT:+1}" ]; then
        if [ "${#SC_COMMENT}" -gt 255 ]; then
            SC_COMMENT_TRUNCATE=$(echo "${SC_COMMENT}" | cut -c1-255)
        else
            SC_COMMENT_TRUNCATE=$SC_COMMENT
        fi
        iptables -A "${SC_NAME}_new" -m comment --comment="${SC_COMMENT_TRUNCATE}" "$@"
    else
        iptables -A "${SC_NAME}_new" "$@"
    fi
    SC_ADD_COUNT=$((${SC_ADD_COUNT} + 1))
    if [ "${SC_V}" = 1 ]; then
        # Don't output too often
        if [ "$((${SC_ADD_COUNT} % 10))" = "0" ]; then
            echo -n "." >&2
        fi
    fi
}

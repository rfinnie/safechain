#!/bin/sh
########################################################################
# Copyright (C) 2013-2020 Canonical Ltd., Ryan Finnie
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Lesser General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this program.  If not, see
# <https://www.gnu.org/licenses/>.
#
# Usage (assuming subchain.sh):
#
# . "$(dirname "$(readlink -f "$0")")/safechain.sh"
# sc_preprocess subchain
# sc_add_rule subchain -d $HOST $SSH -j ACCEPT
# sc_add_rule subchain ...
# sc_postprocess subchain
#
# You are still responsible for creating "subchain" (the "jump chain")
# ahead of time.  When everything goes right, any "sc_add_rule subchain"
# rules added will live in the "subchain_live" chain, and a jump from
# "subchain" to "subchain_live" will automatically be maintained.
#
# When run from the terminal, verbose output will be produced.
########################################################################

set -e
set -u

# Only be verbose if stderr is a terminal
if [ -t 2 ]; then
    SC_V_TERM=1
else
    SC_V_TERM=0
fi
SC_V="${SC_V:-${SC_V_TERM}}"

# Newer iptables requires -w
# https://utcc.utoronto.ca/~cks/space/blog/linux/IptablesWOptionFumbles
SC_IPTABLES_OPTS="${SC_IPTABLES_OPTS:-"-w"}"

SC_CURRENT_CHAIN_V4=""
SC_CURRENT_CHAIN_V6=""

# Set up the environment before adding new rules.
# Do not call this directly.  Instead see sc_preprocess, sc6_preprocess
# and sc46_preprocess below.
_sc_cmd_preprocess() {
    SC_CMD="$1"
    SC_NAME="$2"
    if [ "${SC_CMD}" = "ip6tables" ]; then
      SC_DISPLAY_NAME="${SC_NAME} (v6)"
      SC_CURRENT_CHAIN="${SC_CURRENT_CHAIN_V6}"
    else
      SC_DISPLAY_NAME="${SC_NAME} (v4)"
      SC_CURRENT_CHAIN="${SC_CURRENT_CHAIN_V4}"
    fi
    # Check to make sure we're starting clean
    if [ -n "${SC_CURRENT_CHAIN}" ]; then
      echo "${SC_CURRENT_CHAIN} not finished!  Cowardly refusing to continue." >&2
      echo "Looks like sc_preprocess was called without finishing sc_postprocess first." >&2
      echo "This was most likely caused by an error in the script layout." >&2
      exit 1
    fi
    if [ "${SC_V}" = 1 ]; then echo "[$(date +'%H:%M:%S.%N')] ${SC_DISPLAY_NAME}: Running sanity checks" >&2; fi
    # Check for jump chain (must exist)
    if ! "${SC_CMD}" ${SC_IPTABLES_OPTS} -n -L ${SC_NAME} >/dev/null 2>/dev/null; then
        echo "${SC_NAME} does not exist!  Cowardly refusing to continue." >&2
        echo "Please examine ${SC_CMD}-save and figure out what went wrong." >&2
        exit 1
    fi
    # Create the live chain if it doesn't exist (system boot)
    "${SC_CMD}" ${SC_IPTABLES_OPTS} -N ${SC_NAME}_live 2>/dev/null || true
    # Check for old chain (must not exist)
    if "${SC_CMD}" ${SC_IPTABLES_OPTS} -n -L ${SC_NAME}_old >/dev/null 2>/dev/null; then
        echo "${SC_NAME}_old exists!  Cowardly refusing to continue." >&2
        echo "Please examine ${SC_CMD}-save and figure out what went wrong." >&2
        exit 1
    fi
    # Check for new chain (must not exist)
    if "${SC_CMD}" ${SC_IPTABLES_OPTS} -n -L ${SC_NAME}_new >/dev/null 2>/dev/null; then
        echo "${SC_NAME}_new exists!  Cowardly refusing to continue." >&2
        echo "Please examine ${SC_CMD}-save and figure out what went wrong." >&2
        exit 1
    fi
    if [ "${SC_V}" = 1 ]; then echo "[$(date +'%H:%M:%S.%N')] ${SC_DISPLAY_NAME}: Creating new chain" >&2; fi
    "${SC_CMD}" ${SC_IPTABLES_OPTS} -N ${SC_NAME}_new
    SC_ADD_COUNT=0
    SC_COUNT_PRINTED=0
    if [ "${SC_CMD}" = "ip6tables" ]; then
      SC_CURRENT_CHAIN_V6="${SC_NAME}"
    else
      SC_CURRENT_CHAIN_V4="${SC_NAME}"
    fi
}
sc_preprocess() {
    _sc_cmd_preprocess iptables "$@"
}
sc6_preprocess() {
    _sc_cmd_preprocess ip6tables "$@"
}
sc46_preprocess() {
    _sc_cmd_preprocess iptables "$@"
    _sc_cmd_preprocess ip6tables "$@"
}

# All the magic needed to move the new rules into place.
# Do not call this directly.  Instead see sc_postprocess,
# sc6_postprocess and sc46_postprocess below.
_sc_cmd_postprocess() {
    SC_CMD="$1"
    SC_NAME="$2"
    if [ "${SC_CMD}" = "ip6tables" ]; then
      SC_DISPLAY_NAME="${SC_NAME} (v6)"
      SC_CURRENT_CHAIN="${SC_CURRENT_CHAIN_V6}"
    else
      SC_DISPLAY_NAME="${SC_NAME} (v4)"
      SC_CURRENT_CHAIN="${SC_CURRENT_CHAIN_V4}"
    fi
    if [ ! "${SC_NAME}" = "${SC_CURRENT_CHAIN}" ]; then
      echo "${SC_NAME} != ${SC_CURRENT_CHAIN}!  Typo?  Bailing out." >&2
      exit 1
    fi
    if [ "${SC_V}" = 1 -a "${SC_COUNT_PRINTED}" = 0 ]; then
      echo " ${SC_ADD_COUNT} rules added" >&2
      SC_COUNT_PRINTED=1
    fi
    if [ "${SC_V}" = 1 ]; then echo "[$(date +'%H:%M:%S.%N')] ${SC_DISPLAY_NAME}: Making new chain live" >&2; fi
    # The new ruleset is now running after this command succeeds
    "${SC_CMD}" ${SC_IPTABLES_OPTS} -I ${SC_NAME} -j ${SC_NAME}_new
    # When this happens, the jump to ${SC_NAME}_live in the jump chain
    # is automatically renamed to ${SC_NAME}_old at the same time.
    "${SC_CMD}" ${SC_IPTABLES_OPTS} -E ${SC_NAME}_live ${SC_NAME}_old
    # When this happens, the jump to ${SC_NAME}_new in the jump chain is
    # automatically renamed to ${SC_NAME}_live at the same time.
    "${SC_CMD}" ${SC_IPTABLES_OPTS} -E ${SC_NAME}_new ${SC_NAME}_live
    if [ "${SC_V}" = 1 ]; then echo "[$(date +'%H:%M:%S.%N')] ${SC_DISPLAY_NAME}: Removing old chain" >&2; fi
    # As noted above, this used to be a jump to ${SC_NAME}_live, until
    # the rename.  Note that this rule might not exist, e.g. during
    # first boot.
    "${SC_CMD}" ${SC_IPTABLES_OPTS} -D ${SC_NAME} -j ${SC_NAME}_old 2>/dev/null || true
    # If everything went well, there should be no more references to
    # this chain, and a flush/delete will succeed.
    "${SC_CMD}" ${SC_IPTABLES_OPTS} -F ${SC_NAME}_old
    "${SC_CMD}" ${SC_IPTABLES_OPTS} -X ${SC_NAME}_old
    if [ "${SC_CMD}" = "ip6tables" ]; then
      SC_CURRENT_CHAIN_V6=""
    else
      SC_CURRENT_CHAIN_V4=""
    fi
    if [ "${SC_V}" = 1 ]; then echo "[$(date +'%H:%M:%S.%N')] ${SC_DISPLAY_NAME}: Done!" >&2; fi
}
sc_postprocess() {
    _sc_cmd_postprocess iptables "$@"
}
sc6_postprocess() {
    _sc_cmd_postprocess ip6tables "$@"
}
sc46_postprocess() {
    _sc_cmd_postprocess iptables "$@"
    _sc_cmd_postprocess ip6tables "$@"
}

# Wrapper for "iptables -A", redirecting to the new chain.
# Do not call this directly.  Instead see sc_add_rule, sc6_add_rule and
# sc46_add_rule below.
_sc_cmd_add_rule() {
    SC_CMD="$1"; shift
    SC_NAME="$1"; shift
    if [ "${SC_CMD}" = "ip6tables" ]; then
      SC_CURRENT_CHAIN="${SC_CURRENT_CHAIN_V6}"
    else
      SC_CURRENT_CHAIN="${SC_CURRENT_CHAIN_V4}"
    fi
    if [ ! "${SC_NAME}" = "${SC_CURRENT_CHAIN}" ]; then
      echo "${SC_NAME} != ${SC_CURRENT_CHAIN}!  Typo?  Bailing out." >&2
      exit 1
    fi
    if [ "${SC_V}" = 1 -a ${SC_ADD_COUNT} -eq 0 ]; then
      echo -n "[$(date +'%H:%M:%S.%N')] ${SC_NAME}: Populating new chain..." >&2
    fi
    if [ -n "${SC_COMMENT:+1}" ]; then
        if [ "${#SC_COMMENT}" -gt 255 ]; then
            SC_COMMENT_TRUNCATE=$(echo "${SC_COMMENT}" | cut -c1-255)
        else
            SC_COMMENT_TRUNCATE=$SC_COMMENT
        fi
        "${SC_CMD}" ${SC_IPTABLES_OPTS} -A "${SC_NAME}_new" -m comment --comment="${SC_COMMENT_TRUNCATE}" "$@"
    else
        "${SC_CMD}" ${SC_IPTABLES_OPTS} -A "${SC_NAME}_new" "$@"
    fi
    SC_ADD_COUNT=$((${SC_ADD_COUNT} + 1))
    if [ "${SC_V}" = 1 ]; then
        # Don't output too often
        if [ "$((${SC_ADD_COUNT} % 10))" = "0" ]; then
            echo -n "." >&2
        fi
    fi
}
sc_add_rule() {
    _sc_cmd_add_rule iptables "$@"
}
sc6_add_rule() {
    _sc_cmd_add_rule ip6tables "$@"
}
sc46_add_rule() {
    _sc_cmd_add_rule iptables "$@"
    _sc_cmd_add_rule ip6tables "$@"
}

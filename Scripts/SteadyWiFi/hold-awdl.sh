#!/bin/bash
set -eu

# The pipe's write end is owned by Chiaki. EOF releases the lease even if Chiaki crashes.
hold_steady_wifi() (
    local ifconfig=$1 lock=$2 restore=0 status
    /usr/bin/shlock -f "$lock" -p "${BASHPID:-$$}" || return 1

    # shellcheck disable=SC2329 # Invoked by the EXIT trap.
    cleanup() {
        local result=$?
        if [[ "$restore" == 1 ]] && ! "$ifconfig" awdl0 up; then
            printf 'Could not restore awdl0.\n' >&2
            result=1
        fi
        /bin/rm -f "$lock"
        exit "$result"
    }
    trap cleanup EXIT
    trap 'exit 0' HUP INT TERM

    while :; do
        status=$("$ifconfig" awdl0) || return 1
        case "${status%%$'\n'*}" in
            *'<UP,'*|*'<UP>'*)
                restore=1
                "$ifconfig" awdl0 down || return 1
                ;;
        esac

        # A readable pipe means the app released the lease. A timeout lets us
        # check whether macOS brought AWDL back up. Bash 3 reports both as 1.
        /usr/bin/perl -T -e '
            my $readable = "";
            vec($readable, fileno(STDIN), 1) = 1;
            exit(select($readable, undef, undef, 2) == 0 ? 0 : 1);
        ' || return 0
    done
)

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    [[ "$EUID" == 0 && "$#" == 0 ]] || exit 1
    hold_steady_wifi /sbin/ifconfig /var/run/io.github.chiaki-ng.steady-wifi.lock
fi

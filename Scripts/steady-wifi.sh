#!/bin/bash
set -euo pipefail

helper_dir=/Library/PrivilegedHelperTools
helper="$helper_dir/io.github.chiaki-ng.steady-wifi"
policy=/private/etc/sudoers.d/chiaki-ng-steady-wifi
lock=/var/run/io.github.chiaki-ng.steady-wifi.lock

if [[ "$EUID" != 0 || "$#" != 1 || "$1" != install && "$1" != uninstall ]]; then
    printf 'Usage: sudo %s install|uninstall\n' "$0" >&2
    exit 2
fi

# Do not replace or remove the helper while it owns a paused interface.
if ! /usr/bin/shlock -f "$lock" -p "$$"; then
    printf 'End the active Steady Wi-Fi session before changing the helper.\n' >&2
    exit 1
fi
staged_policy=''
cleanup() {
    /bin/rm -f "$lock"
    if [[ -n "$staged_policy" ]]; then
        /bin/rm -f "$staged_policy"
    fi
}
trap cleanup EXIT

if [[ "$1" == uninstall ]]; then
    /bin/rm -f "$policy" "$helper"
    printf 'Steady Wi-Fi helper removed.\n'
    exit 0
fi

account=${SUDO_USER:-}
if [[ -z "$account" || "$account" == root || ! "$account" =~ ^[A-Za-z0-9_][A-Za-z0-9_-]*$ ]]; then
    printf 'Run the installer with sudo from your macOS account.\n' >&2
    exit 1
fi
script_dir="$(cd "$(/usr/bin/dirname "$0")" && pwd -P)"
if [[ ! -d "$helper_dir" ]]; then
    /usr/bin/install -d -o root -g wheel -m 0755 "$helper_dir"
fi
staged_policy=$(/usr/bin/mktemp /private/etc/sudoers.d/.chiaki-ng-steady-wifi.XXXXXX)
printf '%s ALL=(root) NOPASSWD: %s ""\n' "$account" "$helper" > "$staged_policy"
/usr/sbin/chown root:wheel "$staged_policy"
/bin/chmod 0440 "$staged_policy"
/usr/sbin/visudo -cf "$staged_policy"
/usr/bin/install -o root -g wheel -m 0755 "$script_dir/SteadyWiFi/hold-awdl.sh" "$helper"
/bin/mv -f "$staged_policy" "$policy"
printf 'Steady Wi-Fi helper installed. Enable it in Chiaki Settings > Network.\n'

#!/usr/bin/env sh
set -eu

package_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
launcher="$package_dir/+ops/+core/OpenSeesSPMatlab.sh"
if [ ! -f "$launcher" ]; then
    echo "The OpenSeesSP MATLAB launcher was not found below $package_dir" >&2
    exit 1
fi

exec sh "$launcher" "$@"

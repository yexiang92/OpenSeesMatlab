#!/usr/bin/env sh
set -eu

if [ "$#" -ne 2 ] || [ "$1" -lt 2 ] 2>/dev/null; then
    echo "usage: OpenSeesSPMatlab.sh PROCESSES model.m" >&2
    exit 2
fi

processes=$1
script=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
package_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
native_dir="$package_dir/derived/macos-aarch64"
worker="$native_dir/OpenSeesSPWorker"
matlab=${OPENSEES_MATLAB_EXECUTABLE:-matlab}
mpiexec=${OPENSEES_MPIEXEC:-mpiexec}

if [ ! -x "$worker" ]; then
    echo "OpenSeesSPWorker was not found in $native_dir" >&2
    exit 1
fi
command -v "$matlab" >/dev/null 2>&1 || {
    echo "MATLAB was not found automatically. Set OPENSEES_MATLAB_EXECUTABLE." >&2
    exit 1
}
command -v "$mpiexec" >/dev/null 2>&1 || {
    echo "mpiexec was not found automatically. Set OPENSEES_MPIEXEC." >&2
    exit 1
}

# Make bundled native dependencies visible only to this MPI job.
PATH="$native_dir:$PATH"
export PATH
export OPENSEES_BACKEND=sp

escaped_root=$(printf '%s' "$package_dir" | sed "s/'/''/g")
escaped_script=$(printf '%s' "$script" | sed "s/'/''/g")
matlab_code="addpath('$escaped_root','-begin');OpenSeesNexus.setBackend('sp');run('$escaped_script')"
exec "$mpiexec" -n 1 "$matlab" -batch "$matlab_code" \
    : -n "$((processes - 1))" "$worker"

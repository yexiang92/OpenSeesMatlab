#!/usr/bin/env sh
set -eu

if [ "$#" -ne 2 ] || [ "$1" -lt 2 ] 2>/dev/null; then
    echo "usage: OpenSeesSPMatlab.sh PROCESSES model.m" >&2
    exit 2
fi

processes=$1
script=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
core_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
native_dir="$core_dir/derived/macos-aarch64"
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

escaped_script=$(printf '%s' "$script" | sed "s/'/''/g")
matlab_code="run('$escaped_script')"
ops_dir=$(dirname "$core_dir")
if [ "$(basename "$ops_dir")" = "+ops" ]; then
    toolbox_dir=$(dirname "$ops_dir")
    escaped_toolbox=$(printf '%s' "$toolbox_dir" | sed "s/'/''/g")
    matlab_code="addpath('$escaped_toolbox');$matlab_code"
fi
matlab_code="ops.core.setBackend('sp');$matlab_code"
exec "$mpiexec" -n 1 "$matlab" -batch "$matlab_code" \
    : -n "$((processes - 1))" "$worker"

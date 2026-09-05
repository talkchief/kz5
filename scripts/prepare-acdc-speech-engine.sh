#!/usr/bin/env bash
# Isolated offline-media build only; no system binary install or service change.
set -Eeuo pipefail
build_root=${1:-/usr/local/src/kazoo5-installer}
[[ $build_root == /* && $build_root != / && $build_root != /opt && $build_root != /usr ]] || {
    printf 'Use a dedicated absolute build cache directory\n' >&2; exit 1;
}
speech_source="$build_root/espeak-ng-1.52.0"
speech_revision=4870adfa25b1a32b4361592f1be8a40337c58d6c
for command_name in git cmake gcc g++ make; do
    command -v "$command_name" >/dev/null || { printf 'Missing build dependency: %s\n' "$command_name" >&2; exit 1; }
done
install -d -m 0755 -- "$build_root"
[[ ! -L $speech_source ]] || { printf 'Refusing symlink source tree\n' >&2; exit 1; }
if [[ ! -d $speech_source ]]; then
    git clone --depth 1 --branch 1.52.0 https://github.com/espeak-ng/espeak-ng.git "$speech_source"
fi
[[ $(git -C "$speech_source" rev-parse HEAD) == "$speech_revision" ]] || {
    printf 'Pinned speech source revision mismatch\n' >&2; exit 1;
}
git -C "$speech_source" diff --quiet --exit-code HEAD -- || { printf 'Speech source contains local changes\n' >&2; exit 1; }
cmake -S "$speech_source" -B "$speech_source/build" -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF -DUSE_MBROLA=OFF \
    -DUSE_LIBPCAUDIO=OFF -DUSE_LIBSONIC=OFF -DUSE_SPEECHPLAYER=OFF \
    -DCMAKE_INSTALL_PREFIX="$speech_source/stage"
cmake --build "$speech_source/build" --parallel 1
ESPEAK_DATA_PATH="$speech_source/build" "$speech_source/build/src/espeak-ng" --version
printf 'Speech executable: %s\nSpeech data parent: %s\n' "$speech_source/build/src/espeak-ng" "$speech_source/build"

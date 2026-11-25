#!/usr/bin/env bash

set -euo pipefail

export LC_ALL=C

if [[ $(uname -s)-$(uname -m) != Linux-x86_64 ]]; then
  printf 'Build this bundle on Linux x86-64.\n' >&2
  exit 1
fi

cd -- "$(dirname -- "$0")/../.."
build_dir=${DUNE_BUILD_DIR:-_build}
source_dir=examples/music_player
name=music-player-linux-x86_64
archive=$build_dir/$name.tar.gz

dune build --build-dir "$build_dir" --profile release "$source_dir/music_player.exe"

stage=$(mktemp -d -- "$build_dir/.music-player.XXXXXXXX")
trap 'rm -rf -- "$stage"' EXIT
app=$stage/$name
mkdir -p -- "$app/assets" "$app/shaders" "$app/lib"
install -m 755 "$build_dir/default/$source_dir/music_player.exe" "$app/music_player"
install -m 644 "$source_dir/assets/DejaVuSans.ttf" "$source_dir/assets/LICENSE.md" "$app/assets/"
install -m 644 "$source_dir/shaders/player.vert.spv" "$source_dir/shaders/player.frag.spv" "$app/shaders/"
install -m 644 LICENSE "$app/LICENSE"

copy_library() {
  local soname=$1 path=$2
  # Use the target system's C library and ELF loader.
  case "$soname" in
    ld-linux*.so.*|libc.so.*|libm.so.*|libmvec.so.*|libdl.so.*|libpthread.so.*|\
    librt.so.*|libresolv.so.*|libutil.so.*|libanl.so.*|libBrokenLocale.so.*)
      return 0 ;;
  esac
  cp -L -- "$path" "$app/lib/$soname"
}

copy_linked_libraries() {
  local deps soname path
  deps=$(ldd "$1")
  if grep -q '=> not found' <<< "$deps"; then
    printf 'Could not find required libraries for %s:\n%s\n' "$1" "$deps" >&2
    exit 1
  fi
  while IFS=$'\t' read -r soname path; do
    copy_library "$soname" "$path"
  done < <(awk '$2 == "=>" && $3 ~ /^\// {
    name = $1
    sub(/^[[:space:]]*[^[:space:]]+[[:space:]]+=>[[:space:]]+/, "")
    sub(/[[:space:]]+\(0x[0-9a-f]+\)$/, "")
    print name "\t" $0
  }' <<< "$deps")
}

copy_linked_libraries "$app/music_player"

# SDL_mixer can load decoder libraries at runtime. ldd does not list them.
# Look for the names used by this build rather than fixing their versions.
mixer=$app/lib/libSDL3_mixer.so.0
if [[ -f "$mixer" ]]; then
  cache=$(PATH="$PATH:/usr/sbin:/sbin" ldconfig -p)
  while read -r soname; do
    path=$(awk -v n="$soname" '$1 == n && /x86-64/ {
      sub(/^.* => /, "")
      print
      exit
    }' <<< "$cache")
    if [[ -n "$path" ]]; then
      copy_library "$soname" "$path"
      copy_linked_libraries "$path"
    else
      printf 'Could not find optional codec library %s.\n' "$soname" >&2
    fi
  done < <(strings "$mixer" | awk '/^lib(FLAC|mpg123|vorbisfile|opusfile)\.so(\.[0-9]+)*$/ && !seen[$0]++')
fi

printf '%s\n' '#!/bin/sh' 'set -eu' \
  'app=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)' \
  'export LD_LIBRARY_PATH="$app/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"' \
  'exec "$app/music_player" "$@"' > "$app/run"
chmod 755 "$app/run"

tar -C "$stage" -czf "$stage/$name.tar.gz" "$name"
mv -fT -- "$stage/$name.tar.gz" "$archive"
printf 'Bundle: %s\n' "$archive"

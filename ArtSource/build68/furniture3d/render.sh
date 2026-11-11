#!/bin/zsh
set -euo pipefail
art_source="${0:A:h}"
art_output="${1:?Usage: render.sh OUTPUT_DIRECTORY [KIND]}"
art_cache="/Volumes/AI作品素材/开发缓存/本机编译缓存/catlife/design68/art3d"
python3 -c 'import os; assert os.path.ismount("/Volumes/AI作品素材"), "Required external disk is not mounted"'
mkdir -p "$art_cache/modules" "$art_cache/tmp"
# Swift 6.4.2 traps when TMPDIR contains these non-ASCII volume names.
art_tmp_link="/private/tmp/catlife-art3d-tmp"
if [[ -e "$art_tmp_link" || -L "$art_tmp_link" ]]; then
    [[ -L "$art_tmp_link" && "$(readlink "$art_tmp_link")" == "$art_cache/tmp" ]] || {
        print -u2 "Temporary cache link exists with an unexpected target: $art_tmp_link"
        exit 1
    }
else
    ln -s "$art_cache/tmp" "$art_tmp_link"
fi
export TMPDIR="$art_tmp_link/"
export CLANG_MODULE_CACHE_PATH="$art_cache/modules"
xcrun swiftc -O -module-cache-path "$art_cache/modules" "$art_source/render_furniture.swift" -o "$art_cache/render-furniture"
if (( $# > 1 )); then
    "$art_cache/render-furniture" "$art_output" "$2"
else
    "$art_cache/render-furniture" "$art_output"
fi

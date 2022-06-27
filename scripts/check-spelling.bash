#!/bin/bash

pushd "$(dirname "$0")" >/dev/null

ROOT="$(pwd -P)"/..
cd $ROOT

# from https://en.wikipedia.org/wiki/Commonly_misspelled_English_words
FILE="$ROOT/scripts/misspellings.txt"

echo "checking spelling in $1"

check_file=$1

function check_spelling {
    correct=$(echo "$1" | cut -f1 -d"|")
    bad=$(echo "$1" | cut -f2 -d"|")
    bad_grep=${bad// /|}
    bad_sed=${bad// /\\|}

    matches=$(grep --no-messages -lw "$bad_grep" $check_file)
    if [ -n "$matches" ]; then
        [ $(basename $check_file) = $(basename $FILE) ] && continue
        file $check_file | grep -q "ASCII text" || continue
        echo "  fixing $check_file $bad_grep with $correct"
        sed -i "s/$bad_sed/$correct/g" $check_file
    fi
}

while read LINE; do
    check_spelling "$LINE"
done < $FILE

popd >/dev/null

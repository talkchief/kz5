#!/bin/bash

# script {MKDOCS_INDEX} [{DIR},...]
YML=$1

shift

for dir in "$@";
do
    $(find "$dir" -name "dev.yml" -not -empty -print0 | sort -z | xargs -r0 cat >> "$YML")
done

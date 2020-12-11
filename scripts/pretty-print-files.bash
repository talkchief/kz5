#!/bin/bash
# pretty print list of files
# usage: pretty-print-files "Text" [file]+
# Text
# - file.1
# - file.2

set -e

echo $1
for file in "${@:2}"
do
    echo "- " $(echo $file | sed -e 's!//!/!')
done

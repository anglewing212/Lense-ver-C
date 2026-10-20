#!/bin/zsh
set -eu
cd "${0:A:h:h}"
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
sources=(Sources/Lense/*.swift)
sources=(${sources:#Sources/Lense/Main.swift})
swiftc "${sources[@]}" Tests/AppLifecycle.swift -o "$check_dir/check-app"
"$check_dir/check-app"

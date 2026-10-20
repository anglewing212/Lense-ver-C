#!/bin/zsh
set -eu
cd "${0:A:h:h}"
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
swiftc Sources/Lense/Core.swift Sources/Lense/Service.swift Sources/Lense/Annotations.swift Sources/Lense/Agent.swift Sources/Lense/AnswerLayout.swift Tests/main.swift -o "$check_dir/check"
"$check_dir/check"

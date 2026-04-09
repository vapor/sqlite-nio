#!/usr/bin/env bash

set -e
IFS="$(printf '\n')"
git stash push || true
git checkout main
git pull
lines="$(swift package plugin --allow-writing-to-package-directory --allow-network-connections 'all:443' vendor-sqlite -v 2>&1 | tee /dev/tty | command ggrep -P 'Current version|Found valid update')"
curver="$(echo "${lines}" | command ggrep -Po '(?<=Current version: )\d+\.\d+\.\d+')"
newver="$(echo "${lines}" | command ggrep -Po '(?<=Found valid update: )\d+\.\d+\.\d+')"
[[ -n "${curver}" && -n "${newver}" ]] || exit 1
git checkout -b sqlite-${newver}
git add Sources/VaporCSQLite
git commit -m "Embed sqlite amalgamation ${newver} source code"
git push
git checkout main
open -u "https://github.com/vapor/sqlite-nio/compare/main...sqlite-${newver}?quick_pull=1&title=Embed%20sqlite%20amalgamation%20${newver}%20source%20code&body=Update%20embedded%20SQLite%20from%20${curver}%20to%20${newver}%20%28%5bSQLite%20release%20notes%5d%28https%3a%2f%2fsqlite.org%2freleaselog%2f$(echo "${newver}" | tr '.' '_').html%29%29.&labels=semver-patch"


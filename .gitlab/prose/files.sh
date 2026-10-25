#!/usr/bin/env bash
# List tracked prose, generated examples, and rendered documentation.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
reports=${1:-prose-reports}
mkdir -p "$reports"
source_files="$reports/source-files.txt"
: > "$source_files"
while IFS= read -r -d '' file; do
    case "$file" in
        examples/*/*) continue ;;
    esac
    case "$file" in
        README.md|CHANGELOG.md|docs/src/*.md|examples/*.jl|examples/*.md|src/*.jl|ext/*.jl|docs/make.jl)
            test -f "$file"
            printf '%s\n' "$file" >> "$source_files" ;;
    esac
done < <(git ls-files -z)
test -s "$source_files"
test -s docs/build/index.html
test -d docs/src/examples
find docs/src/examples -type f -name '*.md' -print | sort > "$reports/generated-files.txt"
test -s "$reports/generated-files.txt"
cat "$source_files" "$reports/generated-files.txt" | sort -u > "$reports/cspell-files.txt"
find docs/build -type f -name '*.html' -print | sort > "$reports/html-files.txt"
test -s "$reports/html-files.txt"
cat "$source_files" "$reports/generated-files.txt" "$reports/html-files.txt" | sort -u > "$reports/vale-files.txt"

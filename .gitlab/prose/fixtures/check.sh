#!/usr/bin/env bash
# Verify spelling failures, reviewed terms, and filename language detection.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
cspell_args=(lint --root="$scratch" --config="$root/.gitlab/prose/cspell.json" --no-progress --no-cache)

# A misspelled docstring must fail and include the correct spelling.
printf '"""Read and recieve the result."""\nf() = 1\n' > "$scratch/unpublished.jl"
if cspell "${cspell_args[@]}" "$scratch/unpublished.jl" > "$scratch/spelling.log" 2>&1; then
    echo 'cspell missed a docstring spelling error.' >&2
    exit 1
else
    test "$?" -eq 1
fi
grep -Fq 'Unknown word (recieve)' "$scratch/spelling.log"
grep -Fq 'receive' "$scratch/spelling.log"

# Reviewed names and correctly spelled code identifiers remain accepted.
cat > "$scratch/names.md" <<'MARKDOWN'
Compute the admittance with PowerImpedance and PSCAD.
An unfamiliar name such as Quorvexium has no known correction.
MARKDOWN
cat > "$scratch/names.jl" <<'JULIA'
using PowerImpedance
value = getproperty(network, :frequency)
JULIA
cspell "${cspell_args[@]}" "$scratch/names.md" "$scratch/names.jl"

# An existing identifier spelling is accepted only in its source file.
mkdir -p "$scratch/src/Network/Components/machine"
printf 'value::IntialStates1\n' > "$scratch/src/Network/Components/machine/SynchronousMachine.jl"
cspell "${cspell_args[@]}" "$scratch/src/Network/Components/machine/SynchronousMachine.jl"
cp "$scratch/src/Network/Components/machine/SynchronousMachine.jl" "$scratch/other.jl"
if cspell "${cspell_args[@]}" "$scratch/other.jl" > "$scratch/other.log" 2>&1; then
    echo 'cspell accepted a spelling outside its source file.' >&2
    exit 1
else
    test "$?" -eq 1
fi
grep -Fq 'Unknown word (Intial)' "$scratch/other.log"

# A checkout folder ending in .jl must preserve each file's language.
checkout="$scratch/PowerImpedance.jl/PowerImpedance.jl"
mkdir -p "$checkout"
cat > "$checkout/example.sh" <<'SHELL'
#!/usr/bin/env bash
case value in
    value) ;;
esac
SHELL
printf 'document.addEventListener("mouseout", () => {});\n' > "$checkout/example.js"
printf 'Read the [execution report](../local/validation-refoundation/report.md).\n' > "$checkout/example.md"
cspell "${cspell_args[@]}" "$checkout/example.sh" "$checkout/example.js" "$checkout/example.md"

# All four languages must still report spelling errors in prose.
printf '# Read and recieve the result.\n' >> "$checkout/example.sh"
printf '// Read and recieve the result.\n' >> "$checkout/example.js"
printf '\nRead and recieve the result.\n' >> "$checkout/example.md"
cp "$scratch/unpublished.jl" "$checkout/unpublished.jl"
if cspell "${cspell_args[@]}" "$checkout/example.sh" "$checkout/example.js" \
    "$checkout/example.md" "$checkout/unpublished.jl" > "$scratch/languages.log" 2>&1; then
    echo 'cspell skipped prose under a Julia checkout directory.' >&2
    exit 1
else
    test "$?" -eq 1
fi
test "$(grep -c 'Unknown word (recieve)' "$scratch/languages.log")" -eq 4

# File selection includes generated Markdown and keeps HTML for Vale.
git init --quiet "$scratch/repository"
mkdir -p "$scratch/repository/docs/src/examples" "$scratch/repository/docs/build" \
    "$scratch/repository/.gitlab/prose/styles"
printf 'Maintained prose.\n' > "$scratch/repository/README.md"
printf 'Generated prose.\n' > "$scratch/repository/docs/src/examples/example.md"
printf '<p>Generated prose.</p>\n' > "$scratch/repository/docs/build/index.html"
printf '{}\n' > "$scratch/repository/.gitlab/prose/cspell.json"
printf 'reviewed\n' > "$scratch/repository/.gitlab/prose/words.txt"
printf 'extends: existence\n' > "$scratch/repository/.gitlab/prose/styles/Example.yml"
git -C "$scratch/repository" add README.md .gitlab
(cd "$scratch/repository" && bash "$root/.gitlab/prose/files.sh" "$scratch/selection")
grep -Fxq README.md "$scratch/selection/cspell-files.txt"
grep -Fxq docs/src/examples/example.md "$scratch/selection/cspell-files.txt"
grep -Fxq docs/build/index.html "$scratch/selection/vale-files.txt"
! grep -Eq '\.html$|^\.gitlab/prose/' "$scratch/selection/cspell-files.txt"

# Missing or malformed configuration and missing inputs must fail.
if cspell "${cspell_args[@]}" --config="$scratch/missing.json" "$scratch/names.md" > "$scratch/config.log" 2>&1; then
    echo 'cspell accepted a missing configuration.' >&2
    exit 1
fi
grep -Fq 'Configuration Error' "$scratch/config.log"
printf '{broken json\n' > "$scratch/malformed.json"
if cspell "${cspell_args[@]}" --config="$scratch/malformed.json" "$scratch/names.md" > "$scratch/malformed.log" 2>&1; then
    echo 'cspell accepted a malformed configuration.' >&2
    exit 1
fi
grep -Fq 'Configuration Error' "$scratch/malformed.log"
if cspell "${cspell_args[@]}" "$scratch/missing.md" > "$scratch/missing-input.log" 2>&1; then
    echo 'cspell accepted a missing input.' >&2
    exit 1
fi
echo 'Spelling checks passed.'

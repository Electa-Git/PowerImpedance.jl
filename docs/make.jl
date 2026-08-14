ENV["GKSwstype"] = "100"

using Documenter
using Documenter: Remotes
using Logging
using PowerImpedance
using TOML

global_logger(PowerImpedance._relative_path_logger(current_logger()))

const ROOT_DIR = normpath(joinpath(@__DIR__, ".."))
const DOCS_SRC_DIR = joinpath(@__DIR__, "src")
const BUILD_DIR = joinpath(@__DIR__, "build")

const GITLAB_HOST = "gitlab.kuleuven.be"
const REPOSITORY_PATH = get(
    ENV,
    "CI_PROJECT_PATH",
    "electa/controlgroup/hvdcstability_dev.jl"
)
const REPOSITORY_URL = get(
    ENV,
    "CI_PROJECT_URL",
    "https://$(GITLAB_HOST)/$(REPOSITORY_PATH)"
)
const CANONICAL_URL = get(
    ENV,
    "CI_PAGES_URL",
    "https://electa.pages.gitlab.kuleuven.be/controlgroup/hvdcstability_dev.jl"
)

const REPOSITORY_GROUP = "electa/controlgroup"
const REPOSITORY_NAME = "hvdcstability_dev.jl"
const GITLAB_REMOTE = Remotes.GitLab(GITLAB_HOST, REPOSITORY_GROUP, REPOSITORY_NAME)

const EXAMPLES_SRC = joinpath(ROOT_DIR, "examples")
const EXAMPLES_DOC = joinpath(DOCS_SRC_DIR, "examples")
const CHANGELOG_SRC = joinpath(ROOT_DIR, "CHANGELOG.md")
const CHANGELOG_DOC = joinpath(DOCS_SRC_DIR, "CHANGELOG.md")
const TODO_SRC = joinpath(ROOT_DIR, "TODO.md")
const TODO_DOC = joinpath(DOCS_SRC_DIR, "TODO.md")
const BIBLIOGRAPHY_FILE = joinpath(DOCS_SRC_DIR, "bibliography.bib")

const HAS_CHANGELOG = isfile(CHANGELOG_SRC)
const HAS_TODO = isfile(TODO_SRC)
const HAS_BIBLIOGRAPHY = isfile(BIBLIOGRAPHY_FILE)

const LITERATE_EXAMPLE_FILES = (
    "P2P_HVDC_ALT.jl",
    "P2P_HVDC_Gridspace.jl",
    "IEEE39bus_Gridspace.jl",
    "Gridspace_uncertainty.jl",
    "SmallSignal_Gridspace.jl"
)

const LITERATE_EXAMPLE_PATHS = [joinpath(EXAMPLES_SRC, file)
                                for file in LITERATE_EXAMPLE_FILES
                                if isfile(joinpath(EXAMPLES_SRC, file))]

const HAS_LITERATE_EXAMPLES = !isempty(LITERATE_EXAMPLE_PATHS)

if HAS_LITERATE_EXAMPLES
    using Literate
end

if HAS_CHANGELOG
    using Changelog
end

if HAS_BIBLIOGRAPHY
    using DocumenterCitations
end

function load_project_metadata()
    project_toml = TOML.parsefile(joinpath(ROOT_DIR, "Project.toml"))
    authors = get(project_toml, "authors", String[])
    return (
        name = get(project_toml, "name", "PowerImpedance"),
        version = get(project_toml, "version", "dev"),
        authors = isempty(authors) ?
                  "PowerImpedance contributors" :
                  join(authors, ", ")
    )
end

function running_in_ci()
    return get(ENV, "CI", "false") == "true"
end

function open_in_default_browser(path::AbstractString)
    url = startswith(path, "file://") ? path : "file://" * abspath(path)

    cmd = if Sys.isapple()
        `open $url`
    elseif Sys.iswindows()
        `cmd /c start "" $url`
    elseif Sys.islinux()
        `xdg-open $url`
    else
        nothing
    end

    isnothing(cmd) && return false

    try
        run(pipeline(cmd; stdout = devnull, stderr = devnull))
        return true
    catch err
        @warn "Failed to open the documentation in the default browser." exception = (
            err, catch_backtrace())
        return false
    end
end

function strip_literate_footer(content::AbstractString; replacement::AbstractString = "")
    return replace(
        content,
        r"(?ms)^---\s*\n\*This page was generated using \[Literate\.jl\]\(.*?\)\.\*\s*$" =>
            replacement
    )
end

function postprocess_literate_markdown(content::AbstractString)
    strip_literate_footer(content; replacement = "Back to [Examples](index.md)\n")
end

function tutorial_title(path::AbstractString)
    content = read(path, String)
    matchobj = match(r"(?m)^#\s+(.+)$", content)

    if !isnothing(matchobj)
        return String(matchobj.captures[1])
    end

    stem = splitext(basename(path))[1]
    return titlecase(replace(stem, "_" => " ", "-" => " "))
end

function write_tutorial_index!(examples)
    lines = ["# Examples", ""]
    push!(lines, "This section is generated from the scripts in `examples/`.", "")

    for (title, relative_path) in examples
        push!(lines, "- [$title]($relative_path)")
    end

    write(joinpath(EXAMPLES_DOC, "index.md"), join(lines, "\n") * "\n")
end

function build_example_pages()
    HAS_LITERATE_EXAMPLES || return nothing

    rm(EXAMPLES_DOC; recursive = true, force = true)
    mkpath(EXAMPLES_DOC)

    for path in sort(LITERATE_EXAMPLE_PATHS)
        Literate.markdown(
            path,
            EXAMPLES_DOC;
            documenter = true,
            postprocess = postprocess_literate_markdown
        )
    end

    tutorial_files = sort(
        filter(
        file -> endswith(file, ".md") && file != "index.md",
        readdir(EXAMPLES_DOC)
    ),
    )

    isempty(tutorial_files) && return nothing

    examples = [(tutorial_title(joinpath(EXAMPLES_DOC, file)), file)
                for file in tutorial_files]

    write_tutorial_index!(examples)

    example_pages = Any["Overview" => "examples/index.md"]

    for (title, relative_path) in examples
        push!(example_pages, title => "examples/$relative_path")
    end

    return "Examples" => example_pages
end

function generate_changelog!()
    HAS_CHANGELOG || return nothing

    Changelog.generate(
        Changelog.Documenter(),
        CHANGELOG_SRC,
        CHANGELOG_DOC;
        repo = REPOSITORY_PATH
    )

    return "Changelog" => "CHANGELOG.md"
end

function copy_todo!()
    HAS_TODO || return nothing

    cp(TODO_SRC, TODO_DOC; force = true)

    return "TODO" => "TODO.md"
end

function html_assets()
    candidates = [
        "assets/citations.css",
        "assets/favicon.ico",
        "assets/custom.css",
        "assets/custom.js"
    ]

    return filter(asset -> isfile(joinpath(DOCS_SRC_DIR, asset)), candidates)
end

function sanitize_rendered_log_paths(content::AbstractString)
    location = r"(?m)(└ @ [^\s<]+) (?:~|/)[^\r\n<]*/(src|ext|docs|examples|test)/([^\r\n<]+:\d+)"
    return replace(content, location => s"\1 \2/\3")
end

function sanitize_rendered_log_paths!(directory::AbstractString)
    for (root, _, files) in walkdir(directory)
        for file in files
            endswith(file, ".html") || continue
            path = joinpath(root, file)
            content = read(path, String)
            sanitized = sanitize_rendered_log_paths(content)
            content == sanitized || write(path, sanitized)
        end
    end
    return nothing
end

function build_pages()
    pages = Any[
        "Home" => "index.md",
        "Introduction" => "introduction.md"
    ]

    manual_pages = Any[
        "Network construction" => "network.md",
        "Power-flow initialization" => "initialization.md",
        "Impedance and stability analysis" => "results.md",
        "Parametric and uncertainty studies" => "gridspace.md",
        "Package extensions" => "package_extensions.md",
        "Fundamental concepts" => "manual/fundamental_concepts.md"
    ]

    tutorials_page = build_example_pages()
    isnothing(tutorials_page) || push!(manual_pages, tutorials_page)
    push!(pages, "Manual" => manual_pages)

    push!(
        pages,
        "Components" => Any[
            "Voltage sources" => "source.md",
            "Lumped impedance" => "impedance.md",
            "Transformer" => "transformer.md",
            "Transmission lines and cables" => "transmission_line.md",
            "Modular multilevel converter" => "MMC.md",
            "Two-level converter" => "TLC.md"
        ]
    )

    if isfile(joinpath(DOCS_SRC_DIR, "reference.md"))
        push!(pages, "API Reference" => "reference.md")
    end

    push!(pages, "Classic scalar interface" => "legacy.md")

    development_pages = Any[
        "Docstrings" => "developers/docstrings.md",
        "Conventions" => "developers/conventions.md"
    ]

    todo_page = copy_todo!()
    isnothing(todo_page) || push!(development_pages, todo_page)

    changelog_page = generate_changelog!()
    isnothing(changelog_page) || push!(development_pages, changelog_page)

    push!(pages, "Developers" => development_pages)

    if HAS_BIBLIOGRAPHY && isfile(joinpath(DOCS_SRC_DIR, "bibliography.md"))
        push!(pages, "Bibliography" => "bibliography.md")
    end

    return pages
end

function makedocs_plugins()
    HAS_BIBLIOGRAPHY || return Any[]

    return [CitationBibliography(BIBLIOGRAPHY_FILE; style = :numeric)]
end

function math_engine()
    return MathJax3(
        Dict(
        :loader => Dict("load" => ["[tex]/physics"]),
        :tex => Dict(
            "inlineMath" => [["\$", "\$"], ["\\(", "\\)"]],
            "tags" => "ams",
            "packages" => ["base", "ams", "autoload", "physics"]
        ),
        :chtml => Dict(:scale => 1.1)
    ),
    )
end

metadata = load_project_metadata()

DocMeta.setdocmeta!(
    PowerImpedance,
    :DocTestSetup,
    :(using PowerImpedance);
    recursive = true
)

makedocs(;
    modules = [PowerImpedance],
    authors = metadata.authors,
    sitename = "$(metadata.name).jl",
    repo = GITLAB_REMOTE,
    format = Documenter.HTML(;
        canonical = CANONICAL_URL,
        edit_link = "main",
        assets = html_assets(),
        mathengine = math_engine(),
        prettyurls = running_in_ci(),
        footer = "[$(metadata.name).jl]($(REPOSITORY_URL)) v$(metadata.version) supported by the Etch Competence Hub of EnergyVille, financed by the Flemish Government.",
        size_threshold = nothing
    ),
    pages = build_pages(),
    clean = true,
    plugins = makedocs_plugins(),
    checkdocs = :exports,
    pagesonly = true
)

sanitize_rendered_log_paths!(BUILD_DIR)

if !running_in_ci()
    open_in_default_browser(joinpath(BUILD_DIR, "index.html")) ||
        @warn "Documentation built, but the browser could not be opened automatically."
end

@info "Finished docs build."

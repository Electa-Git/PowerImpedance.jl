using Documenter

deploydocs(;
    root = @__DIR__,
    repo = "github.com/Electa-Git/PowerImpedance.jl.git",
    devbranch = "main",
    versions = ["stable" => "v^", "v#.#", "v#.#.#"],
    push_preview = false,
    deploy_config = Documenter.GitLab()
)

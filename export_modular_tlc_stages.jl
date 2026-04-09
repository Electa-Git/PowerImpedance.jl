using Pkg
project_root = isfile(joinpath(string(@__DIR__), "Project.toml")) ? string(@__DIR__) : pwd()
Pkg.activate(project_root)

using PowerImpedanceACDC
using TOML
using LinearAlgebra
using ForwardDiff
using SciMLBase
using Plots

const DEFAULT_BRANCH = "pq"   # "dcq" or "pq"
const DEFAULT_STAGE  = "support"  # "base", "filters", "pll", "delay", "support"

const OUTDIR = joinpath(project_root, "validation_exports")
mkpath(OUTDIR)

const BRANCH = length(ARGS) >= 1 ? lowercase(ARGS[1]) : DEFAULT_BRANCH
const STAGE  = length(ARGS) >= 2 ? lowercase(ARGS[2]) : DEFAULT_STAGE

const PIType = isdefined(PowerImpedanceACDC, :PIControl) ?
    PowerImpedanceACDC.PIControl :
    PowerImpedanceACDC.PI_control

const LEGACY_DIR = joinpath(@__DIR__, "validation_exports_legacy")

function default_legacy_op_path(branch::AbstractString, stage::AbstractString)
    return joinpath(
        LEGACY_DIR,
        "legacy_$(branch)_$(stage)_operating_point.toml",
    )
end

function default_legacy_adm_path(branch::AbstractString, stage::AbstractString)
    return joinpath(
        LEGACY_DIR,
        "legacy_$(branch)_$(stage)_admittance.tsv",
    )
end

const OP_PATH = length(ARGS) >= 3 ? abspath(ARGS[3]) : default_legacy_op_path(BRANCH, STAGE)
const LEGACY_Y_PATH = length(ARGS) >= 4 ? abspath(ARGS[4]) : default_legacy_adm_path(BRANCH, STAGE)

function read_operating_point(path::AbstractString)
    return TOML.parsefile(path)
end

function read_freqs_from_tsv(path::AbstractString)
    lines = readlines(path)
    data = [split(line, '\t') for line in lines[2:end]]
    return parse.(Float64, getindex.(data, 1))
end

function element_y(elem, s::Complex)
    Id = Matrix{ComplexF64}(I, size(elem.A, 1), size(elem.A, 1))
    Y = elem.C * ((s * Id - elem.A) \ elem.B) + elem.D

    conv = elem.element_model
    elec = conv.elec

    vACbase = elec.vACbase_LL_RMS * sqrt(2 / 3)
    iACbase = 2 * elec.Sbase / (3 * vACbase)
    iDCbase = elec.Sbase / elec.vDCbase

    Y = Matrix{ComplexF64}(Y)

    Y[1, :] .*= iDCbase
    Y[:, 1] ./= elec.vDCbase

    Y[2:3, :] .*= iACbase
    Y[:, 2:3] ./= vACbase

    return Y
end

function tlc_plot_convention(Y::AbstractMatrix)
    return [transpose(Y[1, :]); transpose(-Y[2, :]); transpose(-Y[3, :])]
end

function save_admittance_tsv(path::AbstractString, freqs_hz, Ys)
    open(path, "w") do io
        header = ["freq_hz"]
        for r in 1:3, c in 1:3
            push!(header, "Y$(r)$(c)_re")
            push!(header, "Y$(r)$(c)_im")
        end
        println(io, join(header, '\t'))

        for (f, Y) in zip(freqs_hz, Ys)
            row = String[string(f)]
            for r in 1:3, c in 1:3
                push!(row, string(real(Y[r, c])))
                push!(row, string(imag(Y[r, c])))
            end
            println(io, join(row, '\t'))
        end
    end
end

function linearize_tlc!(elem::PowerImpedanceACDC.Element,
                        m::PowerImpedanceACDC.TLC,
                        setpoint::PowerImpedanceACDC.SetPoint)

    inputs = PowerImpedanceACDC.pftoinputs(m, setpoint)
    inputs_vec = collect(values(inputs))
    init = PowerImpedanceACDC.orderedinitialvalues(m; setpoint, inputs)

    function f_equil!(du, u, p)
        x_nt = NamedTuple{PowerImpedanceACDC.statenames(m)}(u)
        inputs_nt = NamedTuple{PowerImpedanceACDC.inputnames(m)}(p.inputs)
        PowerImpedanceACDC.equilibrium_state_space!(du, x_nt, inputs_nt, m, p.setpoint)
        return nothing
    end

    p_equil = (; inputs = inputs_vec, setpoint = setpoint)

    println("Starting to solve for steady-state solution")
    prob = NonlinearProblem(f_equil!, collect(values(init)), p_equil)
    sol = solve(prob; maxiters = 20, abstol = 1e-6, reltol = 1e-6)

    if !SciMLBase.successful_retcode(sol)
        error("steady-state solution not found! retcode=$(sol.retcode)")
    end

    println("steady-state solution found!")

    equilibrium = sol.u[1:PowerImpedanceACDC.n_states(m)]

    nb_states = PowerImpedanceACDC.n_states(m)
    nb_inputs = PowerImpedanceACDC.n_inputs(m)
    nb_elec_inputs = PowerImpedanceACDC.n_elec_inputs(m)
    nb_addit_inputs = nb_inputs - nb_elec_inputs
    nb_outputs = PowerImpedanceACDC.n_outputs(m)

    function h!(F, xu)
        x = xu[1:end-nb_inputs]
        u = xu[end-nb_inputs+1:end]

        x_nt = NamedTuple{PowerImpedanceACDC.statenames(m)}(x)
        inputs_nt = NamedTuple{PowerImpedanceACDC.inputnames(m)}(u)

        PowerImpedanceACDC.state_space!(@view(F[1:nb_states]), x_nt, inputs_nt, m)
        PowerImpedanceACDC.outputequations!(@view(F[nb_states+1:end]), x_nt, inputs_nt, m)

        return nothing
    end

    ha = xu -> begin
        F = fill(zero(eltype(xu)), nb_states + nb_outputs)
        h!(F, xu)
        return F
    end

    jac = zeros(nb_states + nb_outputs, nb_states + nb_inputs)
    ForwardDiff.jacobian!(jac, ha, [equilibrium; inputs_vec])

    elem.A = ComplexF64.(jac[1:nb_states, 1:nb_states])
    elem.B = ComplexF64.(jac[1:nb_states, nb_states+1:end-nb_addit_inputs])
    elem.C = ComplexF64.(jac[nb_states+1:end, 1:nb_states])
    elem.D = ComplexF64.(jac[nb_states+1:end, nb_states+1:end-nb_addit_inputs])

    return elem
end

function make_case(branch::AbstractString, stage::AbstractString, op)
    Vm = 220 / sqrt(3)
    Vdc = 640.0

    Ztrafo_base = 220^2 / 100
    Lf = 0.08 * Ztrafo_base / (2π * 50)
    Rf = 0.01 * 0.08 * Ztrafo_base

    elec = PowerImpedanceACDC.ElectricalTLC(
        Vᵈᶜ = Vdc,
        Vₘ = Vm,
        Lᵣ = Lf,
        Rᵣ = Rf,
        Sbase = 100,
        vACbase_LL_RMS = 220,
        vDCbase = Vdc,
    )

    if stage in ("filters", "pll", "delay", "support")
        vac_filter = PowerImpedanceACDC.Butterworth(order = 2, ωc = 0.5e4)
        iac_filter = PowerImpedanceACDC.Butterworth(order = 2, ωc = 0.5e4)
        meas = PowerImpedanceACDC.MeasurementTLC(vac = vac_filter, iac = iac_filter)
    else
        meas = PowerImpedanceACDC.MeasurementTLC()
    end

    if stage in ("pll", "delay", "support")
        pll = PowerImpedanceACDC.PLLSynchronization(
            pi_ctrl = PIType(Kp = 0.397887357729738, Ki = 7.957747154594767),
            filter = PowerImpedanceACDC.Butterworth(order = 2, ωc = 2π * 80),
        )
    else
        pll = PowerImpedanceACDC.NoSynchronization()
    end

    innerVoltage = PowerImpedanceACDC.NoInnerVoltageControl()

    innerCurrent = PowerImpedanceACDC.InnerCurrentPIControl(
        pi_ctrl = PIType(Kp = 0.254647908947033, Ki = 0.8),
    )

    if stage in ("delay", "support")
        mod = PowerImpedanceACDC.PadeModulation(
            timeDelay = 200e-6,
            padeOrderNum = 3,
            padeOrderDen = 3,
        )
    else
        mod = PowerImpedanceACDC.NoModulation()
    end

    Vac_amp = op["Vac_kV_amp"]
    Pac = op["Pac_MW"]
    Qac = op["Qac_Mvar"]
    θac = op["theta_rad"]
    Vdc_op = op["Vdc_kV"]
    Pdc = op["Pdc_MW"]

    q_ref_pu = -Qac / elec.Sbase
    p_ref_pu = Pac / elec.Sbase
    vdc_ref_pu = Vdc_op / elec.vDCbase
    vac_ref_pu = Vac_amp / (elec.vACbase_LL_RMS * sqrt(2 / 3))

    local outerActive
    local outerReactive

    if branch == "dcq"
        outerActive = PowerImpedanceACDC.OuterActiveVdcControl(
            pi_ctrl = PIType(Kp = 5.0, Ki = 5.0),
            vdc_ref = vdc_ref_pu,
        )

        if stage == "support"
            outerReactive = PowerImpedanceACDC.OuterReactiveQControl(
                pi_ctrl = PIType(Kp = 0.04, Ki = 40.0),
                q_ref = q_ref_pu,
                support = PowerImpedanceACDC.VoltageSupportLag(
                    K = 5.0,
                    ωc = 1 / 0.5,
                    vac_ref = vac_ref_pu,
                ),
            )
        else
            outerReactive = PowerImpedanceACDC.OuterReactiveQControl(
                pi_ctrl = PIType(Kp = 0.04, Ki = 40.0),
                q_ref = q_ref_pu,
            )
        end

    elseif branch == "pq"
        if stage == "support"
            outerActive = PowerImpedanceACDC.OuterActivePowerControl(
                pi_ctrl = PIType(Kp = 0.04, Ki = 40.0),
                p_ref = p_ref_pu,
                support = PowerImpedanceACDC.FrequencySupportLag(
                    Kω = 5.0,
                    ωc = 1 / 0.5,
                ),
            )
        else
            outerActive = PowerImpedanceACDC.OuterActivePowerControl(
                pi_ctrl = PIType(Kp = 0.04, Ki = 40.0),
                p_ref = p_ref_pu,
            )
        end

        outerReactive = PowerImpedanceACDC.OuterReactiveQControl(
            pi_ctrl = PIType(Kp = 0.04, Ki = 40.0),
            q_ref = q_ref_pu,
        )
    else
        error("Unsupported branch '$branch'. Use 'dcq' or 'pq'.")
    end

    setpoint = PowerImpedanceACDC.SetPoint(
        Pac = Pac,
        Qac = Qac,
        θac = θac,
        Vac = Vac_amp,
        Pdc = Pdc,
        Vdc = Vdc_op,
    )

    elem = PowerImpedanceACDC.tlc(
        elec = elec,
        meas = meas,
        synch = pll,
        outerActive = outerActive,
        outerReactive = outerReactive,
        innerVoltage = innerVoltage,
        innerCurrent = innerCurrent,
        mod = mod,
        setpoint = setpoint,
    )

    linearize_tlc!(elem, elem.element_model, setpoint)

    return elem
end




function read_admittance_tsv(path::AbstractString)
    lines = readlines(path)
    data = [split(line, '\t') for line in lines[2:end]]

    Ys = Matrix{ComplexF64}[]
    for row in data
        Y = zeros(ComplexF64, 3, 3)
        idx = 2
        for r in 1:3, c in 1:3
            re = parse(Float64, row[idx]); idx += 1
            im = parse(Float64, row[idx]); idx += 1
            Y[r, c] = complex(re, im)
        end
        push!(Ys, Y)
    end
    return Ys
end


relative_error(A::AbstractMatrix, B::AbstractMatrix; atol = 1e-12) =
    norm(A .- B) / max(norm(B), atol)

function plot_relative_error(freqs_hz, Ys_mod, Ys_legacy; label_suffix = "")
    errs = [
        relative_error(Ym, Yl)
        for (Ym, Yl) in zip(Ys_mod, Ys_legacy)
    ]

    plt = plot(
        freqs_hz,
        errs;
        xscale = :log10,
        yscale = :log10,
        linewidth = 2,
        marker = :circle,
        xlabel = "Frequency (Hz)",
        ylabel = "Relative error ‖Y − Yₗₑgacy‖ / ‖Yₗₑgacy‖",
        title = "Relative admittance error vs legacy $(label_suffix)",
        legend = false,
        grid = true,
    )

    return plt
end





function main()
    op = read_operating_point(OP_PATH)

    freqs_hz = read_freqs_from_tsv(LEGACY_Y_PATH)
    Ys_legacy = read_admittance_tsv(LEGACY_Y_PATH)

    elem = make_case(BRANCH, STAGE, op)

    Ys_mod = Matrix{ComplexF64}[]
    for f in freqs_hz
        Y = element_y(elem, 1im * 2π * f)
        push!(Ys_mod, tlc_plot_convention(Y))
    end

    prefix = joinpath(OUTDIR, "modular_$(BRANCH)_$(STAGE)")

    save_admittance_tsv(prefix * "_admittance.tsv", freqs_hz, Ys_mod)

    plt = plot_relative_error(
        freqs_hz,
        Ys_mod,
        Ys_legacy;
        label_suffix = "($(BRANCH), $(STAGE))",
    )

    savefig(plt, prefix * "_relative_error.png")

    println("Wrote:")
    println(prefix * "_admittance.tsv")
    println(prefix * "_relative_error.png")
end

Base.invokelatest(main)


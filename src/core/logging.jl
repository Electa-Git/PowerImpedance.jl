"""
$(TYPEDEF)

Forward log records while replacing host-specific source paths with repository-
relative paths.

$(TYPEDFIELDS)
"""
struct _RelativePathLogger{L <: Logging.AbstractLogger} <: Logging.AbstractLogger
    "Wrapped logger receiving normalized records."
    logger::L

    "Absolute package root used to identify repository files."
    package_root::String
end

"""
$(TYPEDSIGNATURES)

Wrap a logger so displayed source locations do not expose build-host paths.

# Arguments

- `logger`: Logger receiving the forwarded records. Default: the current logger.

# Returns

- A logger that displays package paths relative to the repository root.
"""
function _relative_path_logger(logger::Logging.AbstractLogger = current_logger())
    return _RelativePathLogger(logger, normpath(pkgdir(PowerImpedance)))
end

function Logging.min_enabled_level(logger::_RelativePathLogger)
    Logging.min_enabled_level(logger.logger)
end

function Logging.shouldlog(logger::_RelativePathLogger, level, module_, group, id)
    Logging.shouldlog(logger.logger, level, module_, group, id)
end

function Logging.catch_exceptions(logger::_RelativePathLogger)
    Logging.catch_exceptions(logger.logger)
end

function _display_log_path(filepath, package_root)
    filepath === nothing && return nothing

    path = replace(string(filepath), '\\' => '/')
    root = replace(normpath(package_root), '\\' => '/')
    root_prefix = root * "/"
    startswith(path, root_prefix) && return path[(lastindex(root_prefix) + 1):end]

    for directory in ("src", "ext", "docs", "examples", "test")
        marker = "/$directory/"
        match_range = findlast(marker, path)
        isnothing(match_range) || return path[(first(match_range) + 1):end]
    end

    return basename(path)
end

function Logging.handle_message(
        logger::_RelativePathLogger,
        level,
        message,
        module_,
        group,
        id,
        filepath,
        line;
        kwargs...
)
    return Logging.handle_message(
        logger.logger,
        level,
        message,
        module_,
        group,
        id,
        _display_log_path(filepath, logger.package_root),
        line;
        kwargs...
    )
end

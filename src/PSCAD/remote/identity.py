"""Identify the PSCAD installation and selected Fortran compiler without solving a model."""

import hashlib
import platform
from importlib import metadata
from pathlib import Path

from mhi.common import process
import mhi.pscad


def identify(version, app=None):
    if version != "5.1.0":
        raise ValueError("The PowerImpedance PSCAD adapter supports version 5.1.0")
    executable = Path(process.find_exe("PSCAD", version=version, x64=True)).resolve()
    root = executable.parents[2]
    automation_version = metadata.version("mhi.pscad")
    if automation_version != "3.1.2":
        raise ValueError("The PowerImpedance PSCAD adapter requires mhi.pscad 3.1.2")
    owned = app is None
    try:
        if owned:
            app = mhi.pscad.launch(version=version, x64=True, minimize=True,
                                   splash=False, silence=True, timeout=60)
        if str(app.version) != version:
            raise ValueError("PSCAD launched an unexpected application version")
        fortran_version = "unknown"
        try:
            # Use the saved raw selection so identity is independent of whether
            # this Windows session can decode the detected compiler software.
            fortran_version = str(app._settings({})["fortran_version"])
        except Exception:
            pass
        files = {
            "pscad": executable,
            "master_library": root / "master.pslx",
        }
        result = {
            "schema": "2",
            "version": version,
            "python_version": platform.python_version(),
            "automation_version": automation_version,
            "common_version": metadata.version("mhi.common"),
            "profile": "saved profile; simulation settings supplied explicitly",
            "fortran_version": fortran_version,
        }
        for name, path in files.items():
            result[name + "_path"] = str(path)
            with path.open("rb") as stream:
                result[name + "_sha256"] = hashlib.file_digest(stream, "sha256").hexdigest()
        return result
    finally:
        if owned and app is not None:
            app.quit()

#!/usr/bin/env python
"""
Helper script to validate and (optionally) generate TunableOp tuning data.

Behavior:
- Checks whether an existing TunableOp results file is present and valid for the
  current software stack (PyTorch/ROCm/BLAS versions, etc.).
- If the file is missing or rejected by TunableOp's validators, and an untuned
  file is available, it will run offline tuning to generate a fresh results file.

Configuration via environment variables:
- TUNABLEOP_DIR          : Base directory for tuning files (default: this script's dir)
- TUNABLEOP_RESULTS_FILE : Path to results CSV (default: $TUNABLEOP_DIR/tunableop_results0.csv)
- TUNABLEOP_UNTUNED_FILE : Path to untuned CSV (default: $TUNABLEOP_DIR/tunableop_untuned0.csv)

The script is designed to fail soft: if TunableOp or torch are not available,
it simply logs a message and exits successfully so it never blocks startup.
"""

# pylint: disable=import-error,broad-exception-caught

import os
import sys


def log(msg: str) -> None:
    print(f"[tunableop] {msg}", file=sys.stderr)


def main() -> int:
    try:
        import torch.cuda.tunable as tunable
    except Exception as e:  # pragma: no cover - defensive
        log(f"TunableOp not available (torch or torch.cuda.tunable import failed): {e}")
        return 0

    base_dir = os.environ.get("TUNABLEOP_DIR", os.path.dirname(os.path.abspath(__file__)))
    results_file = os.environ.get(
        "TUNABLEOP_RESULTS_FILE",
        os.path.join(base_dir, "tunableop_results0.csv"),
    )
    untuned_file = os.environ.get(
        "TUNABLEOP_UNTUNED_FILE",
        os.path.join(base_dir, "tunableop_untuned0.csv"),
    )

    # Configure TunableOp to use the requested results file.
    # insert_device_ordinal=True ensures separate files per GPU when needed.
    try:
        tunable.enable(True)
        tunable.tuning_enable(False)
        tunable.record_untuned_enable(False)
        tunable.set_filename(results_file, insert_device_ordinal=True)
    except Exception as e:  # pragma: no cover - very defensive
        log(f"Failed to configure TunableOp: {e}")
        return 0

    # First, try to read the existing tuning data (if any). This will also check
    # the validator lines inside the CSV and reject it if the current software
    # configuration (PyTorch/ROCm/BLAS versions, etc.) does not match.
    try:
        ok = tunable.read_file()
    except Exception as e:  # pragma: no cover
        log(f"read_file() raised exception, treating as invalid: {e}")
        ok = False

    if ok:
        log(f"Existing tuning file is valid for this configuration: {results_file}")
        return 0

    # At this point the file is either missing or rejected by validators.
    # If there is no untuned file to work from, there is nothing more we can do
    # automatically; TunableOp can still tune online during normal execution.
    if not os.path.exists(untuned_file):
        log(
            "No valid tuning file found and untuned file is missing; "
            "skipping offline tuning. TunableOp can still tune online if enabled."
        )
        return 0

    log(
        "Tuning file missing or invalid for current configuration; "
        f"running offline tuning from {untuned_file} -> {results_file}"
    )

    try:
        # Enable tuning and run offline tuning based on the untuned file.
        tunable.tuning_enable(True)
        tunable.record_untuned_enable(False)
        tunable.tune_gemm_in_file(untuned_file)
    except Exception as e:  # pragma: no cover
        log(f"Offline tuning failed: {e}")
        return 0

    log("Offline TunableOp tuning complete.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


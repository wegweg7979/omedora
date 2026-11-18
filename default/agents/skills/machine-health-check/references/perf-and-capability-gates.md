# Perf and capability gates: why a tool says a feature is missing

When a desktop or monitoring tool reports something it should have as absent — btop with
no GPU box, a widget with no reading, a feature that only works under `sudo` — separate
three cases before answering: (a) the backend really is missing, (b) the kernel is
refusing a capability, (c) the UI element is simply not enabled. `sudo` making it work is
evidence for (b), not proof that (a) is false.

## Diagnosis — all read-only, unprivileged

```bash
intel_gpu_top -l                  # the tool's own reader prints its error verbatim
sysctl -n kernel.perf_event_paranoid
ls /sys/bus/event_source/devices/ | grep -iE 'i915|uncore'
strings "$(command -v btop)" | grep -Ei 'intel|i915|fdinfo|PMU'   # which backend is compiled in
```

Measured on `workstation` (i915 / Alder Lake-P, no discrete GPU): with
`kernel.perf_event_paranoid = 2`, `intel_gpu_top -l` prints
`Failed to initialize PMU! (Permission denied)` and btop silently drops Intel GPUs — its
binary carries `src/linux/intel_gpu_top/intel_gpu_top.c`, so it uses the same
`perf_event_open` path on the i915 PMU. The `/sys/class/drm/**` attributes btop also reads
are world-readable, so permissions there are never the problem: do not chase them.

## The fix, and why it has to be shaped this way

The capability the tool wants is `CAP_PERFMON` — exactly why `sudo` worked.

- **Root stays with the user** (see the SKILL.md ground rules). Hand over the lines and
  let them run it; never type a password.
- Durable per-host fix is a sysctl drop-in, which survives image updates because `/etc`
  is merged, not reset:

  ```bash
  echo 'kernel.perf_event_paranoid = 0' | sudo tee /etc/sysctl.d/90-perfmon.conf
  sudo sysctl --system
  intel_gpu_top -l          # as the user: must now list engines, no permission error
  ```

- **`0` is the minimum; `-1` over-grants.** A CPU-wide PMU event needs event access
  allowed (paranoid ≤ 1) and non-`exclude_kernel` events need paranoid < 2; `-1`
  additionally opens raw tracepoint access, which no load graph needs. Try `0` first and
  say what still fails if it does not.
- **`setcap` on the shipped binary cannot work on this image family:** `/` is a read-only
  composefs overlay, so `setcap cap_perfmon+ep /usr/sbin/btop` cannot persist across
  deploys. The alternative that does work is a copy the user owns —
  `cp /usr/sbin/btop ~/.local/bin/btop && sudo setcap cap_perfmon+ep ~/.local/bin/btop` —
  at the cost of a stale copy after every package update and the same capability handed to
  user-run code. Recommend the drop-in; offer the copy only when loosening the sysctl is
  unacceptable.
- **State the trade-off you just accepted:** paranoid=0 lets any local user do system-wide
  perf monitoring. That is acceptable on a single-user laptop and is precisely why the
  privileged run worked.

## The UI half (btop, applies to any self-owning TUI config)

Clearing the gate does not add the box. In a running btop press `5` — "Show GPU boxes" —
or put `gpu0` in `shown_boxes`. `show_gpu_info = "Auto"` only renders a single GPU line
inside the CPU box when no GPU box is shown, so the two are mutually exclusive.

**Edit `btop.conf` only while btop is not running — btop rewrites the whole file on exit**
and silently discards an edit made underneath it.

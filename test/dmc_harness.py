"""
DMC unit-test sandbox: drives nes.apu.APU2A03 directly.

With bus_ref left unset, every sample DMA read returns 0 (a silent sample),
so the harness exercises the channel's control logic and timing only. Each
clock(1) step is followed by a read of $4015 to observe the real status bits.

Used to characterise the timing behind blargg's 7-dmc_basics #19 and
8-dmc_rates windows.

Usage (from the repo root):
  python test/dmc_harness.py
"""
import os
import sys

sys.path.insert(0, os.getcwd())
from nes.apu import APU2A03  # noqa: E402


def new_apu():
    # bus_ref stays None so DMA reads return 0 (a silent sample), which
    # isolates the control logic and timing under test.
    return APU2A03()


def status_of(apu):
    v = apu.readByCPU(0x4015)
    return v, {
        "p1": bool(v & 1), "p2": bool(v & 2), "tri": bool(v & 4),
        "noise": bool(v & 8), "dmc_active": bool(v & 0x10),
        "frame_irq": bool(v & 0x40), "dmc_irq": bool(v & 0x80),
    }


def run_test19():
    print("=== test 19 (one-byte buffer filled immediately if empty) ===")
    apu = new_apu()
    apu.writeByCPU(0x4010, 0x8F)   # rate = max (0xF), DMC IRQ enabled
    apu.writeByCPU(0x4013, 1)      # length register 1 => 17 bytes (sample A)
    apu.writeByCPU(0x4015, 0x10)   # start sample A
    c = 0
    while status_of(apu)[1]["dmc_active"] and c < 2_000_000:
        apu.clock(1); c += 1
    v, s = status_of(apu)
    print(f"  sample A ended at cycle {c}, $4015={hex(v)} dmc_irq={s['dmc_irq']}")
    # delay_dmc 4 + delay 30: only advances the clock, no bearing on the verdict
    for _ in range(54 * 8 * 4 + 30):
        apu.clock(1)
    # restart sample B: a 1-byte sample
    apu.writeByCPU(0x4013, 0)      # length register 0 => 1 byte
    apu.writeByCPU(0x4015, 0x10)   # restart sample B
    v, s = status_of(apu)
    print(f"  [restart B] immediate $4015={hex(v)}  -> expect $80 (dmc_irq=1, dmc_active=0)")
    for i in range(15):
        apu.clock(1)
        v, s = status_of(apu)
        print(f"             +{i+1:2d}cyc $4015={hex(v)} active={s['dmc_active']} dmc_irq={s['dmc_irq']}")


def probe_end(length_n, rate_idx):
    """Return (cycle the sample stopped, cycle the DMC IRQ was raised)."""
    apu = new_apu()
    apu.writeByCPU(0x4010, rate_idx | 0x80)  # DMC IRQ enabled
    apu.writeByCPU(0x4013, length_n)         # length register => length_n*16+1 bytes
    apu.writeByCPU(0x4015, 0x10)
    c = 0
    irq_cycle = None
    while status_of(apu)[1]["dmc_active"] and c < 2_000_000:
        apu.clock(1); c += 1
        if irq_cycle is None and status_of(apu)[1]["dmc_irq"]:
            irq_cycle = c
    return c, irq_cycle


def dmc_rates_check():
    print("=== dmc_rates windows (17 bytes; expect active=1 @135*period-65, active=0 @135*period+25) ===")
    rates = [428, 380, 340, 320, 286, 254, 226, 214, 190, 160, 142, 128, 106, 84, 72, 54]
    for idx, period in enumerate(rates):
        end_c, irq_c = probe_end(1, idx)  # $4013=1 => 17 bytes
        still = period * 8 * 17 - period - 65
        stopped = still + 90
        ok_play = end_c > still
        ok_stop = end_c <= stopped
        flag = "OK " if (ok_play and ok_stop) else "BAD"
        print(f"  rate{idx:2d} period={period:4d} end={end_c:7d} (play_chk@{still} stop_chk@{stopped}) {flag}")


if __name__ == "__main__":
    run_test19()
    print()
    dmc_rates_check()

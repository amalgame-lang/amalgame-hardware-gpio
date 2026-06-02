# amalgame-hardware-gpio

GPIO digital I/O for Linux single-board computers (Raspberry Pi 1→5
and friends), the first package in the **`Amalgame.Hardware`** family.

Backed by **libgpiod v2** on the GPIO character device
(`/dev/gpiochip*`) — the kernel-blessed userspace interface, safe on
every Pi including the Pi 5 (whose GPIO sits behind the RP1 chip, so
the old `/dev/gpiomem` register mmap no longer works). The deprecated
sysfs `/sys/class/gpio` interface is not used.

The API deliberately mirrors the `Amalgame.Mcu` HAL (see
`docs/proposals/amc-embedded.md` in the amc repo) so the same pin code
reads the same on a Pi today and on bare-metal MCUs later.

## Install

```sh
amc package add hardware-gpio
# or
amc package add github.com/amalgame-lang/amalgame-hardware-gpio@v0.1.0
```

### System dependency: libgpiod **v2** (≥ 2.0)

This package links `libgpiod` **2.x**. Check what you have:

```sh
pkg-config --modversion libgpiod   # want 2.x
```

| Distro | libgpiod in apt | Action |
|---|---|---|
| Debian Trixie+, Ubuntu 24.10+ | 2.x | `sudo apt install libgpiod-dev` |
| **Raspberry Pi OS / Debian Bookworm, Ubuntu 24.04 LTS** | **1.6 (incompatible)** | build 2.x from source (below) |

Build 2.x from source on Bookworm:

```sh
curl -sSLO https://mirrors.edge.kernel.org/pub/software/libs/libgpiod/libgpiod-2.2.4.tar.gz
tar xzf libgpiod-2.2.4.tar.gz && cd libgpiod-2.2.4
./configure --prefix=/usr/local --enable-tools=yes
make && sudo make install && sudo ldconfig
```

> libgpiod 1.x and 2.x have incompatible APIs; this package targets 2.x
> only. A 1.6 fallback shim is out of scope (see the amc memory note).

## Usage

```amalgame
import Amalgame.Hardware

Gpio.PinMode(17, PinMode.Output)        // BCM GPIO17
Gpio.PinMode(27, PinMode.InputPullup)   // button to GND on GPIO27

while (true) {
    Gpio.Toggle(17)
    if (Gpio.DigitalRead(27) == Level.Low) {   // pressed
        Console.WriteLine("pressed")
    }
    // ... wait 500ms (see examples/blink.am for an inlined sleep) ...
}
Gpio.Close()
```

See [`examples/blink.am`](examples/blink.am).

## API

**Digital I/O (Phase 1)**

| Method | Description |
|---|---|
| `Gpio.UseChip(path)` | Pick the gpiochip device. Default `/dev/gpiochip0` (correct for Pi 1→5 on current kernels). |
| `Gpio.PinMode(pin, mode)` → `bool` | Configure direction + pull. `false` if the line can't be requested (busy / bad offset / no chip). |
| `Gpio.DigitalWrite(pin, level)` | Drive an output pin (`Level.Low` / `Level.High`). |
| `Gpio.DigitalRead(pin)` → `Level` | Read a pin's level. |
| `Gpio.Toggle(pin)` | Flip an output pin. |
| `Gpio.Release(pin)` | Release one line, keep the chip open. |
| `Gpio.Close()` | Release all lines and close the chip (idempotent). |
| `Gpio.Backend()` → `string` | libgpiod version string (diagnostics). |

**Edge events (Phase 2)**

| Method | Description |
|---|---|
| `Gpio.WatchEdge(pin, edge)` → `bool` | Arm kernel edge detection (`Edge.Rising` / `Falling` / `Both`). Re-requests the line as an input; sets no internal pull. |
| `Gpio.WaitEdge(timeoutMs)` → `GpioEvent` | Block up to `timeoutMs` (negative = forever, 0 = poll) for the next edge on any watched pin. Returns a sentinel with `IsTimeout() == true` on timeout. |
| `Gpio.PollEdges()` → `List<GpioEvent>` | Non-blocking: drain all edges queued on watched pins, oldest-first. |

Enums / records:
- `PinMode`: `Input`, `Output`, `InputPullup`, `InputPulldown`.
- `Level`: `Low` (0), `High` (1).
- `Edge`: `Rising`, `Falling`, `Both` (`Both` is a trigger only; a delivered event is always `Rising`/`Falling`).
- `GpioEvent`: `KindOf()` → `Edge`, `PinOf()` → `int`, `TimestampNsOf()` → `int` (kernel monotonic ns), `IsTimeout()` → `bool`.

See [`examples/button_events.am`](examples/button_events.am) for the edge-event loop.

**I2C (Phase 3)**

I2C master over `/dev/i2c-<bus>`. Instance-based: `new I2c(bus)` holds the open fd. Each op takes the slave `addr` and selects it internally. Bytes cross as `List<int>` (0..255).

```amalgame
let bus = new I2c(1)                    // /dev/i2c-1
for addr in bus.Scan() { /* … */ }
bus.WriteReg(0x68, 0x6B, 0x00)          // wake an MPU-6050
let raw = bus.ReadBytes(0x68, 6)        // burst read
bus.Close()
```

| Method | Description |
|---|---|
| `new I2c(bus)` / `.IsOpen()` | Open `/dev/i2c-<bus>`; `IsOpen()` is `false` if I2C is disabled / not permitted. |
| `.Close()` | Close the bus fd (idempotent). |
| `.WriteByte(addr, value)` → `bool` / `.ReadByte(addr)` → `int` | Single raw byte (read `-1` on error). |
| `.WriteReg(addr, reg, value)` → `bool` / `.ReadReg(addr, reg)` → `int` | Register access. |
| `.WriteBytes(addr, List<int>)` → `bool` / `.ReadBytes(addr, count)` → `List<int>` | Multi-byte (≤256). |
| `.Scan()` → `List<int>` | Probe `0x03..0x77`, return responders (like `i2cdetect`). |

`bus` is the i2c adapter number (the N in `/dev/i2c-N`); on a Pi it's usually `1`. See [`examples/i2c_scan.am`](examples/i2c_scan.am).

**SPI (Phase 4)**

SPI master over `/dev/spidev<bus>.<cs>`. Instance-based: `new Spi(bus, cs)` holds the fd and per-device settings.

```amalgame
let spi = new Spi(0, 0)                 // /dev/spidev0.0
spi.SetMode(0)
spi.SetSpeed(1000000)                   // 1 MHz
let rx = spi.Transfer(tx)              // full-duplex; rx.Count() == tx.Count()
spi.Close()
```

| Method | Description |
|---|---|
| `new Spi(bus, cs)` / `.IsOpen()` / `.Close()` | Open `/dev/spidev<bus>.<cs>`. |
| `.SetMode(0..3)` → `bool` | Clock polarity/phase. |
| `.SetSpeed(hz)` → `bool` | Max clock speed. |
| `.SetBits(n)` → `bool` | Bits per word (usually 8). |
| `.Transfer(List<int>)` → `List<int>` | Full-duplex; returns the bytes clocked in (same length as tx). |

See [`examples/spi_loopback.am`](examples/spi_loopback.am).

**Pin numbering** is the gpiochip line offset; on a Raspberry Pi this
equals the BCM GPIO number (`GPIO17` → `17`).

**Permissions**: the user must be in the `gpio` group (Raspberry Pi OS
adds the default user automatically) or run as root.

## Roadmap

This package grows by phase, each a publishable release under
`Amalgame.Hardware`:

- **v0.1 — GPIO digital I/O** ✅
- **v0.2 — GPIO edge events / interrupts** (`WatchEdge`, `WaitEdge`, `PollEdges`) ✅
- **v0.3 — I2C** (`/dev/i2c-*`) ✅
- **v0.4 — SPI** (`/dev/spidev*`) ✅ ← you are here
- v0.5 — PWM (sysfs) + UART (termios)

> **Design note.** `I2c` and `Spi` are instance-based — their state (the
> device fd + settings) lives on the Amalgame object, and the `@c` blocks
> are thin, stateless syscall wrappers. `Gpio` keeps a flat, Mcu-style
> static API by design; since Amalgame has no static/global state, its
> per-pin handle table necessarily lives in C. The `@c` boundary is kept
> to the irreducible FFI (libgpiod + Linux ioctls); everything else is
> Amalgame.

High-level sensors / displays / motor drivers will live in sibling
packages (`amalgame-hardware-sensors`, `-display`, …). Bare-metal MCU
support is a separate track (`Amalgame.Mcu`, see the amc embedded
proposal).

## License

Apache-2.0 — see [LICENSE](LICENSE). The facade is 100% pure-Amalgame
with one `@c { … }` block that calls libgpiod; no third-party code is
vendored.

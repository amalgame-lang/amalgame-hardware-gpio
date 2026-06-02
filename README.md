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

## API (Phase 1)

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

`PinMode`: `Input`, `Output`, `InputPullup`, `InputPulldown`.
`Level`: `Low` (0), `High` (1).

**Pin numbering** is the gpiochip line offset; on a Raspberry Pi this
equals the BCM GPIO number (`GPIO17` → `17`).

**Permissions**: the user must be in the `gpio` group (Raspberry Pi OS
adds the default user automatically) or run as root.

## Roadmap

This package grows by phase, each a publishable release under
`Amalgame.Hardware`:

- **v0.1 — GPIO digital I/O** ← you are here
- v0.2 — GPIO edge events / interrupts (`WatchEdge`, `WaitEdge`, `PollEdges`)
- v0.3 — I2C (`/dev/i2c-*`)
- v0.4 — SPI (`/dev/spidev*`)
- v0.5 — PWM (sysfs) + UART (termios)

High-level sensors / displays / motor drivers will live in sibling
packages (`amalgame-hardware-sensors`, `-display`, …). Bare-metal MCU
support is a separate track (`Amalgame.Mcu`, see the amc embedded
proposal).

## License

Apache-2.0 — see [LICENSE](LICENSE). The facade is 100% pure-Amalgame
with one `@c { … }` block that calls libgpiod; no third-party code is
vendored.

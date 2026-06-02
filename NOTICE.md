# NOTICE — amalgame-hardware-gpio

## Authorship

Copyright 2026 Bastien Mouget. The Amalgame facade code in this
repository is original work — see `facade.am` and the `amalgame.toml`
manifest.

This package is part of the Amalgame ecosystem
([github.com/amalgame-lang/Amalgame](https://github.com/amalgame-lang/Amalgame)).
It is the first member of the `Amalgame.Hardware` family, adding GPIO
access for Linux single-board computers after amc gained a Linux ARM64
(Raspberry Pi OS 64-bit) release target.

## License

Licensed under the Apache License, Version 2.0 — see `LICENSE`.

## Third-party content

None is vendored. At build time the facade's `@c { … }` block calls
**libgpiod** (LGPL-2.1-or-later), a system library that must be
installed separately (`libgpiod-dev` ≥ 2.0). libgpiod is linked, not
redistributed, by this package.

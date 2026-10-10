# minifin

`minifin` is my minimal take on [Bluefin](https://projectbluefin.io/). Bluefin ships several things I usually just disable.
It is based on Fedora Silverblue (GNOME), keeps Bluefin's shared desktop configuration from [`projectbluefin/common`](https://github.com/projectbluefin/common), and adds only a small set of apps and GNOME extensions.

Published images live at `ghcr.io/jhxnnat/minifin`.

## Differences from Bluefin

- Fewer apps. Only Flatseal and Extension Manager for now.
- Extensions Caffeine and Just Perfection are installed and enabled system-wide at build time.
- Homebrew, Flatpaks, `ujust`, `uupd`, signing, and the promotion flow work exactly as they do on Bluefin.

## Using this image

Switch to a built image:

```bash
sudo bootc switch --transport registry ghcr.io/jhxnnat/minifin:stable-testing
sudo systemctl reboot
```

Then, as your user:

```bash
ujust install-default-apps    # Homebrew: the default Brewfile
ujust install-dev-tools       # Homebrew: the development Brewfile
ujust configure-dev-groups    # add yourself to docker and libvirt
ujust install-config          # re-apply the image defaults, backing up yours
```

First boot unpacks Homebrew and installs the declared Flatpaks; both need a
network connection. Check them with `systemctl status brew-setup.service` and
`systemctl status flatpak-preinstall.service`.

## Image signing

Images are signed with keyless OIDC via Cosign and GitHub Actions. There is no
key to generate or store.

```bash
cosign verify \
  --certificate-identity-regexp="https://github.com/Jhxnnat/minifin/.github/workflows/" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ghcr.io/jhxnnat/minifin:stable
```

Unsigned images fail the promotion gate, so `main → stable` reports
`release/blocked` until signing is restored. Signatures are checked in CI on
the way to `:stable` and **not verified on the device**: the promotion gate is
the only enforcement point, and an installed system pulls its updates over an
unverified transport (`image-info.json`'s `image-ref` is
`ostree-unverified-image:docker://…`).

## Acknowledgements

This image assembles work from across the Universal Blue ecosystem:

- [Project Bluefin](https://projectbluefin.io/)
- [finpilot](https://github.com/projectbluefin/finpilot), the template this repo was generated from.
- [Universal Blue](https://universal-blue.org/)
- [Fedora Silverblue](https://fedoraproject.org/atomic-desktops/silverblue/)
- [bootc](https://containers.github.io/bootc/)

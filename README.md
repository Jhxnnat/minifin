# minifin

`minifin` is a minimal take on [Bluefin](https://projectbluefin.io/): a small
desktop image assembled the same way Bluefin, Aurora, and Bluefin LTS are —
from shared OCI layers rather than by modifying an existing image. It is based
on Fedora Silverblue (GNOME), keeps Bluefin's shared desktop configuration from
[`projectbluefin/common`](https://github.com/projectbluefin/common), and adds
only a small set of apps and GNOME extensions.

Published images live at `ghcr.io/jhxnnat/minifin`.

## What's different from Bluefin

- **Fewer apps.** minifin starts from Fedora Silverblue plus Bluefin's shared
  configuration, without Bluefin's wider app selection. Only Flatseal and
  Extension Manager install on first boot.
- **A small extension set.** Caffeine and Just Perfection are installed and
  enabled system-wide at build time.
- **The same plumbing.** Homebrew, Flatpaks, `ujust`, `uupd`, signing, and the
  promotion flow work exactly as they do on Bluefin.

## What's included

**Build system**

- A build on every push to `main`, publishing `:stable-testing`
- Renovate through `projectbluefin/actions`, updating pinned actions and image
  digests every six hours
- Images older than 90 days pruned automatically
- Pull requests validated for shellcheck, hadolint, Brewfiles, Flatpaks,
  Justfiles, and Renovate config
- Keyless OIDC signing on every published image, enforced at promotion
  ([where the signature is checked](#where-the-signature-is-checked))

**Runtime**

- Homebrew, pre-staged at build time and unpacked on first boot
- Flatpaks declared in `custom/flatpaks/` — Flatseal and Extension Manager —
  installed on first boot
- GNOME Shell extensions from `build/40-gnome-extensions.sh`, enabled
  system-wide
- `ujust` shortcuts for the Brewfiles and for re-applying configuration
- `uupd` for scheduled system updates

## Releases

| Branch   | Image tag         | Audience                       |
| -------- | ----------------- | ------------------------------ |
| `main`   | `:stable-testing` | Testers and release candidates |
| `stable` | `:stable`         | Production                     |

Merging to `main` publishes `:stable-testing`; the promotion PR that follows
publishes `:stable` when merged. Promotion verifies the cosign signature on the
testing image before it reports ready, and refuses to promote at all once `main`
has moved past the commit the promotion PR was built from.

> **Known gap:** the promotion gate checks the digest and the signature only. It
> runs no end-to-end tests, so `release/ready` means "signed and unmodified",
> not "functionally validated".

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
`release/blocked` until signing is restored.

### Where the signature is checked

**In CI, on the way to `:stable` — and not verified on the device.** The
promotion gate is the only enforcement point. An installed system pulls its
updates over an unverified transport (`image-info.json`'s `image-ref` is
`ostree-unverified-image:docker://…`), so `bootc upgrade` does not check the
cosign signature.

That is a deliberate statement of what the image can actually do, not an
oversight. Device-side verification runs through
`/etc/containers/policy.json`, which matches a keyless Fulcio certificate on
`subjectEmail` only — mandatory and exact. A GitHub Actions certificate
identifies its workflow in a URI SAN and carries no email, so no policy entry
can match it, and the inherited policy's `""` catch-all
(`insecureAcceptAnything`) would accept the image regardless. A signed-looking
`image-ref` here would verify nothing while implying it verified something.

Making updates verify on the device means signing with a key the policy can
name: publish with a cosign keypair, merge a `sigstoreSigned` scope for this
namespace into the inherited policy (with `jq`, during
[`build/10-overlay.sh`](build/10-overlay.sh) — never by shipping a whole
`policy.json` through `custom/files/`, which freezes every scope you inherited),
add a `registries.d` entry with `use-sigstore-attachments: true` for it, and
flip `IMAGE_REF` back to `ostree-image-signed:`. Validate that on a real
install before shipping it: a scope that does not match turns `bootc upgrade`
into a hard refusal. `tests/contract/image-signing_test.bats` holds the two
sides together, so changing one without the other fails the suite.

## Customize

Pick the base image on the `Containerfile`'s `FROM` line; that line is the only
place the base is chosen, and `just build` reads the image name and the tag
from it. The Fedora major comes from the base image itself during the build.
Then add to the image:

- **System packages** — `build/20-packages-and-services.sh` ([guide](build/README.md))
- **GNOME extensions** — `build/40-gnome-extensions.sh` ([guide](build/README.md))
- **CLI tools** — `custom/brew/` ([guide](custom/brew/README.md))
- **GUI apps** — `custom/flatpaks/` ([guide](custom/flatpaks/README.md))
- **Commands** — `custom/ujust/` ([guide](custom/ujust/README.md))
- **System files** — `custom/files/` ([guide](custom/files/README.md))
- **Per-user config** — `custom/config/` ([guide](custom/config/README.md))

[build/README.md](build/README.md) also lists the inactive examples (Tailscale,
NVIDIA drivers, a desktop swap) and the steps to activate one.
[The `customize` skill](.agents/skills/customize/SKILL.md) decides which of
those a given package belongs in.

## Local development

Local builds need `podman`, `just`, and `git`. `just test-unit` needs `bats`,
`just lint` needs `shellcheck`, and `just format` needs `shfmt`. Booting a VM
natively needs `qemu-system-x86_64` and OVMF firmware; without QEMU, `run-vm-*`
falls back to a browser console.

```bash
git clone https://github.com/Jhxnnat/minifin.git
cd minifin

just build            # build the container image with Podman
just build-qcow2      # build a QCOW2 disk image from it
just run-vm-qcow2     # boot the disk image in a VM (builds it first if needed)
just build-iso        # build an installer ISO
just run-vm-iso       # boot the ISO in a VM
```

`just --list` shows every recipe. Before opening a pull request:

```bash
just lint               # shellcheck every tracked shell script
just format             # rewrite tracked shell scripts with shfmt
just check              # verify Justfile syntax
just test-unit          # run the contract and template suites
just validate-brewfiles # check custom/brew/ without evaluating it
just validate-flatpaks  # check custom/flatpaks/ against Flathub
```

## Troubleshooting

[The `troubleshooting` skill](.agents/skills/troubleshooting/SKILL.md) covers
build, CI, and runtime failures symptom-first. The two most common first-boot
surprises:

- **No Flatpaks.** `flatpak-preinstall.service` needs a network connection and
  reports success even when it cannot reach Flathub, so a first boot before
  Wi-Fi is configured installs nothing. Reboot once you are online.
- **No `brew`.** `brew-setup.service` unpacks Homebrew on first boot; check its
  status before reaching for a reinstall.

## Community

- [Universal Blue Discord](https://discord.gg/WEu6BdFEtp)
- [bootc discussions](https://github.com/bootc-dev/bootc/discussions)

## Learn more

- [Universal Blue](https://universal-blue.org/)
- [bootc](https://containers.github.io/bootc/)
- [Project Bluefin contributing guide](https://docs.projectbluefin.io/contributing/)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Acknowledgements

This image assembles work from across the Universal Blue ecosystem:

- [Project Bluefin](https://projectbluefin.io/) — for
  [`common`](https://github.com/projectbluefin/common), the shared runtime
  layer; [`actions`](https://github.com/projectbluefin/actions), the reusable
  build, signing, and promotion workflows; and
  [`finpilot`](https://github.com/projectbluefin/finpilot), the template this
  repository was generated from.
- [Universal Blue](https://universal-blue.org/) — for the bootc build system
  and [`ublue-os/brew`](https://github.com/ublue-os/brew), which integrates
  Homebrew with the image.
- [Fedora Silverblue](https://fedoraproject.org/atomic-desktops/silverblue/) —
  for the base image and the GNOME desktop.
- [bootc](https://containers.github.io/bootc/) — for the tooling that turns a
  container image into an atomic operating system.

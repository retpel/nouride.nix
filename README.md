# nouride.nix

[Nouride](https://nouride.com) releases ([nouverse/nouride-releases](https://github.com/nouverse/nouride-releases)) packaged as a Nix flake, for `x86_64-linux` and `aarch64-linux`.

| Output | |
| --- | --- |
| `packages.<system>.nouride` (default) | Standard edition |
| `packages.<system>.nouride-router` | Router edition (in-process Nougate AI Router) |
| `overlays.default` | Adds both packages to `pkgs` |
| `nixosModules.default` | `services.nouride` systemd service |

The upstream binary is unfree. The flake's own packages allow it for just these two; with the overlay, your nixpkgs config has to allow it (e.g. `nixpkgs.config.allowUnfreePredicate`).

## NixOS

```nix
{
  inputs.nouride.url = "github:retpel/nouride.nix";

  outputs = { nixpkgs, nouride, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nouride.nixosModules.default
        {
          services.nouride = {
            enable = true;
            # package = nouride.packages.x86_64-linux.nouride-router;
            environmentFile = "/run/secrets/nouride.env";
          };
        }
      ];
    };
  };
}
```

The daemon runs as `nouride` in `/var/lib/nouride` (`stateDir`), which holds `config.toml` and `.nouride/`. The dashboard listens on `127.0.0.1:18254`; set `host` and `openFirewall` to expose it.

Without the overlay the module uses this flake's package; with `overlays.default` applied it uses `pkgs.nouride`.

## Updating

`sources.json` is bumped by a daily workflow that opens a PR. Pick up new versions with `nix flake update nouride` in your system flake.

Do not use the dashboard's update button on NixOS. It offers itself (the state directory is writable), but the service keeps running the binary from the store, so the version does not change.

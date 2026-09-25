# NixOS module: the systemd service install.sh would set up, minus the self-updater
# (the binary lives in the read-only store — bump sources.json / the flake input instead).
#
# The dashboard's "update" still offers itself: the daemon treats stateDir as its install
# directory, and that is writable. Applying it writes the new release's files into stateDir
# (replacing the `nouride` link until the next activation), but the service keeps running
# cfg.package, so the version does not change. Update through Nix.
self:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.nouride;
  isRouter = (cfg.package.passthru.edition or "standard") == "router";
in
{
  options.services.nouride = {
    enable = lib.mkEnableOption "Nouride, a multi-agent AI daemon";

    package = lib.mkOption {
      type = lib.types.package;
      # `pkgs.nouride` when the overlay is applied, so the build follows the system's nixpkgs
      # (which then needs to allow the unfree licence); otherwise the flake's own build.
      default = pkgs.nouride or self.packages.${pkgs.stdenv.hostPlatform.system}.nouride;
      defaultText = lib.literalExpression "pkgs.nouride or nouride.packages.\${system}.nouride";
      description = ''
        Nouride build to run. Defaults to `pkgs.nouride` when `nouride.overlays.default` is
        applied, else the flake's package. Use the `nouride-router` package for the Router edition.
      '';
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address the dashboard binds to. `0.0.0.0` exposes it on the network.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 18254;
      description = "Dashboard / API port.";
    };

    routerPort = lib.mkOption {
      type = lib.types.port;
      default = 18256;
      description = "Port of the in-process Nougate gateway (Router edition only; set `[nougate] port` to match).";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the dashboard port (and the Nougate port for the Router edition).";
    };

    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/nouride";
      description = ''
        Working directory and HOME of the daemon. It holds `config.toml` (optional) and
        `.nouride/` — the database, secrets and agent packs.
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "nouride";
      description = "User the daemon runs as (created when left at the default).";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "nouride";
      description = "Group the daemon runs as (created when left at the default).";
    };

    environment = lib.mkOption {
      type = with lib.types; attrsOf str;
      default = { };
      example = {
        LOG_LEVEL = "debug";
        TZ = "Asia/Jakarta";
      };
      description = "Extra environment variables for the daemon.";
    };

    environmentFile = lib.mkOption {
      type = with lib.types; nullOr path;
      default = null;
      example = "/run/secrets/nouride.env";
      description = "File with secrets such as bot tokens (`KEY=value` lines), kept out of the store.";
    };

    extraPackages = lib.mkOption {
      type = with lib.types; listOf package;
      default = with pkgs; [
        bash
        coreutils
        findutils
        gnugrep
        gnused
        curl
        git
      ];
      defaultText = lib.literalExpression "with pkgs; [ bash coreutils findutils gnugrep gnused curl git ]";
      description = "Packages on the daemon's PATH, i.e. the commands agents can execute.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users = lib.mkIf (cfg.user == "nouride") {
      nouride = {
        isSystemUser = true;
        group = cfg.group;
        home = cfg.stateDir;
      };
    };
    users.groups = lib.mkIf (cfg.group == "nouride") { nouride = { }; };

    environment.systemPackages = [ cfg.package ];

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall (
      [ cfg.port ] ++ lib.optional isRouter cfg.routerPort
    );

    systemd.tmpfiles.settings.nouride = {
      ${cfg.stateDir}.d = {
        inherit (cfg) user group;
        mode = "0750";
      };
      # The daemon offers agents its own CLI as a tool only when a `nouride` binary sits in the
      # install directory (the parent of `.nouride/`); point it at the current package.
      "${cfg.stateDir}/nouride"."L+".argument = lib.getExe cfg.package;
    };

    systemd.services.nouride = {
      description = "Nouride multi-agent AI daemon";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = cfg.extraPackages;

      environment = {
        HOME = cfg.stateDir;
        HOST = cfg.host;
        PORT = toString cfg.port;
        NOURIDE_SERVICE_KIND = "systemd";
      }
      // cfg.environment;

      startLimitBurst = 5;
      startLimitIntervalSec = 120;

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.stateDir;
        ExecStart = "${lib.getExe cfg.package} start";
        EnvironmentFile = lib.mkIf (cfg.environmentFile != null) cfg.environmentFile;
        Restart = "always";
        RestartSec = 5;
        # In-flight turns are saved on SIGTERM; matches [daemon] shutdown_timeout_ms with headroom.
        TimeoutStopSec = 45;
        KillSignal = "SIGTERM";
        UMask = "0027";
        SyslogIdentifier = "nouride";

        # Same sandbox as the unit `nouride service install` writes (its non-privileged mode).
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only"; # read-only rather than hidden, so a stateDir under /home still works
        ReadWritePaths = [ cfg.stateDir ];
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        RestrictNamespaces = true;
        LockPersonality = true;
      };
    };
  };
}

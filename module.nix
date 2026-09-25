# NixOS module: the systemd service install.sh would set up, minus the self-updater
# (the binary lives in the read-only store — bump sources.json instead).
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
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.nouride;
      defaultText = lib.literalExpression "nouride.packages.\${system}.nouride";
      description = "Nouride build to run. Use the `nouride-router` package for the Router edition.";
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

    systemd.tmpfiles.settings.nouride.${cfg.stateDir}.d = {
      inherit (cfg) user group;
      mode = "0750";
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
        ExecStart = "${lib.getExe cfg.package} run";
        EnvironmentFile = lib.mkIf (cfg.environmentFile != null) cfg.environmentFile;
        Restart = "always";
        RestartSec = 5;
        # In-flight turns are saved on SIGTERM; matches [daemon] shutdown_timeout_ms with headroom.
        TimeoutStopSec = 45;
        KillSignal = "SIGTERM";
        UMask = "0027";

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "full";
        ProtectHome = true;
      };
    };
  };
}

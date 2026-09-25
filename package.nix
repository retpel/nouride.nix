{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  edition ? "standard", # "standard" | "router"
}:

let
  sources = lib.importJSON ./sources.json;
  arch =
    {
      x86_64-linux = "x64";
      aarch64-linux = "arm64";
    }
    .${stdenv.hostPlatform.system}
      or (throw "nouride: unsupported system ${stdenv.hostPlatform.system}");
  pname = if edition == "router" then "nouride-router" else "nouride";
  artifact = "${pname}-linux-${arch}";
in
stdenv.mkDerivation {
  inherit pname;
  inherit (sources) version;

  src = fetchurl {
    url = "https://github.com/nouverse/nouride-releases/releases/download/v${sources.version}/${artifact}.tar.gz";
    hash = sources.hashes.${artifact};
  };

  # The tarball has no top-level directory.
  unpackPhase = ''
    runHook preUnpack
    mkdir source
    tar -xzf $src -C source
    runHook postUnpack
  '';
  sourceRoot = "source";

  nativeBuildInputs = [ autoPatchelfHook ];

  # A `bun build --compile` executable: the app lives in the ELF's .bun section, which strip drops.
  dontStrip = true;

  # The daemon looks for dashboard/, skills/ (and frontend/, wa-bridge/ when shipped) next to the
  # real executable, so keep the release layout together and only symlink the binary onto PATH.
  installPhase = ''
    runHook preInstall
    mkdir -p $out/libexec/nouride $out/bin
    cp -r . $out/libexec/nouride/
    ln -s $out/libexec/nouride/nouride $out/bin/nouride
    runHook postInstall
  '';

  passthru = { inherit edition; };

  meta = {
    description =
      "Lightweight multi-agent AI engine in a single daemon"
      + lib.optionalString (edition == "router") " (with the in-process Nougate AI Router)";
    homepage = "https://nouride.com";
    changelog = "https://github.com/nouverse/nouride-releases/releases/tag/v${sources.version}";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "nouride";
  };
}

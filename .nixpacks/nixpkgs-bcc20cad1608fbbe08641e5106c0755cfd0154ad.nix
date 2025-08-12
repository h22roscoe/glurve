{ }:

let pkgs = import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/bcc20cad1608fbbe08641e5106c0755cfd0154ad.tar.gz") { overlays = [  ]; };
in with pkgs;
  let
    APPEND_LIBRARY_PATH = "${lib.makeLibraryPath [  ] }";
    myLibraries = writeText "libraries" ''
      export LD_LIBRARY_PATH="${APPEND_LIBRARY_PATH}:$LD_LIBRARY_PATH"
      
    '';
  in
    buildEnv {
      name = "bcc20cad1608fbbe08641e5106c0755cfd0154ad-env";
      paths = [
        (runCommand "bcc20cad1608fbbe08641e5106c0755cfd0154ad-env" { } ''
          mkdir -p $out/etc/profile.d
          cp ${myLibraries} $out/etc/profile.d/bcc20cad1608fbbe08641e5106c0755cfd0154ad-env.sh
        '')
        elixir erlang rebar3 wget
      ];
    }

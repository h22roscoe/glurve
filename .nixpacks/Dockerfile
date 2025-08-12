FROM ghcr.io/railwayapp/nixpacks:ubuntu-1745885067

ENTRYPOINT ["/bin/bash", "-l", "-c"]
WORKDIR /app/


COPY .nixpacks/nixpkgs-bcc20cad1608fbbe08641e5106c0755cfd0154ad.nix .nixpacks/nixpkgs-bcc20cad1608fbbe08641e5106c0755cfd0154ad.nix
RUN nix-env -if .nixpacks/nixpkgs-bcc20cad1608fbbe08641e5106c0755cfd0154ad.nix && nix-collect-garbage -d

COPY .nixpacks/assets /assets/
ARG NIXPACKS_METADATA
ENV NIXPACKS_METADATA=$NIXPACKS_METADATA

# setup phase
# noop

# install phase
COPY gleam.toml /app/gleam.toml
COPY manifest.toml /app/manifest.toml
RUN  sh /assets/get-gleam.sh 1.12.0
RUN  gleam deps download

# build phase
COPY . /app/.
RUN  gleam export erlang-shipment





# start
COPY . /app

CMD ["./build/erlang-shipment/entrypoint.sh run"]


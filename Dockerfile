# Write a Dockerfile to run Cosmos Gaia v7.1.0 (https://github.com/cosmos/gaia) 
# in a container. It should download the source code, build it and run without 
# any modifiers (i.e. docker run somerepo/gaia:v7.1.0 should run the daemon) as 
# well as print its output to the console. The build should be security conscious
# (and ideally pass a container image security test such as Anchor)

# Use a multi-stage docker build:
#  - stage 1: create a docker image that can download the Gaia repo
#  - stage 2: copy Gaia's own Dockerfile to build the daemon
#  - stage 3: copy the daemon into a distroless container and run it there

# Use Ubuntu latest per Gaia installation docs
# https://github.com/cosmos/gaia/blob/main/docs/getting-started/installation.md

# STAGE 1
FROM ubuntu:jammy AS gaia-downloader
WORKDIR /src/

# Install dev tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends git=1:2.34.1-1ubuntu1 \
                                               ca-certificates=20211016ubuntu0.22.04.1
RUN git clone -b v7.1.0 https://github.com/cosmos/gaia.git

## STAGE 2
FROM golang:1.19.5-alpine AS gaiad-builder

# Grab the cloned repo from STAGE.1
COPY --from=gaia-downloader /src/gaia/ /src/gaia/

# Copy the install procedure from Gaia's Dockerfile
# https://github.com/cosmos/gaia/blob/main/Dockerfile
WORKDIR /src/gaia/
RUN go mod download

ENV PACKAGES curl=7.87.0-r1 make=4.3-r1 git=2.38.2-r0 libc-dev=0.7.2-r3 bash=5.2.15-r0 
ENV PACKAGES $PACKAGES gcc=12.2.1_git20220924-r4 linux-headers=5.19.5-r0 
ENV PACKAGES $PACKAGES eudev-dev=3.2.11-r4 python3=3.10.9-r1

RUN apk add --no-cache $PACKAGES && \
    CGO_ENABLED=0 make install

# Do the init steps from the gaia quickstart guide
# https://hub.cosmos.network/main/getting-started/quickstart.html
RUN gaiad init CUSTOM_MONKEY --chain-id cosmoshub-4

# Set minimum gas price & peers
RUN sed -i'' 's/minimum-gas-prices = ""/minimum-gas-prices = "0.0025uatom"/' $HOME/.gaia/config/app.toml
RUN sed -i'' 's/persistent_peers = ""/persistent_peers = '"\"$(curl -s https://raw.githubusercontent.com/cosmos/chain-registry/master/cosmoshub/chain.json | jq -r '[foreach .peers.seeds[] as $item (""; "\($item.id)@\($item.address)")] | join(",")')\""'/' $HOME/.gaia/config/config.toml

# Configure State sync, grab a recent block height and hash
RUN sed -i'' 's/enable = false/enable = true/' $HOME/.gaia/config/config.toml
RUN sed -i'' 's/trust_height = 0/trust_height = 13661483/' $HOME/.gaia/config/config.toml
RUN sed -i'' 's/trust_hash = ""/trust_hash = "B08A4F37082775988D2BDD0779C332AC964B15B55555E57AEA07F1D6E1E67F07"/' $HOME/.gaia/config/config.toml
RUN sed -i'' 's/rpc_servers = ""/rpc_servers = "https:\/\/cosmos-rpc.polkachu.com:443,https:\/\/rpc-cosmoshub-ia.cosmosia.notional.ventures:443,https:\/\/rpc.cosmos.network:443"/' $HOME/.gaia/config/config.toml

# Enable prometheus metrics
RUN sed -i'' 's/prometheus = false/prometheus = true/' $HOME/.gaia/config/config.toml

## STAGE 3
# Add to a distroless container
FROM cgr.dev/chainguard/static:latest
COPY --from=gaiad-builder /go/bin/gaiad /usr/local/bin/
COPY --from=gaiad-builder /root/.gaia/ /root/.gaia

EXPOSE 26656 26657 1317 9090
USER 0

ENTRYPOINT ["gaiad", "start", "--x-crisis-skip-assert-invariants"]

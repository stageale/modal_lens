# syntax=docker/dockerfile:1

ARG ELIXIR_IMAGE=hexpm/elixir:1.20.2-erlang-29.0.3-ubuntu-resolute-20260707
ARG UV_IMAGE=ghcr.io/astral-sh/uv:0.11.28

FROM ${UV_IMAGE} AS uv

FROM ${ELIXIR_IMAGE} AS runtime

ENV DEVIAN_FRONTEND=noninteractive \
    MIX_ENV=test \
    UV_PROJECT_ENVIRONMENT=/workspace/.venv \
    UV_PYTHON=3.12.13 \
    UV_LINK_MODE=copy \
    PATH="/workspace/.venv/bin:${PATH}"

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        ca-certificates \
        git \
    && rm -rf /var/lib/apt/lists/*

COPY --from=uv /uv /uvx /usr/local/bin/

WORKDIR /workspace

COPY . .

RUN mix local.hex --force \
    && mix local.rebar --force \
    && mix deps.get \
    && mix compile

RUN uv python install 3.12.13 \
    && uv sync --locked

CMD ["./cmd/test_all.sh"]

# The tools CI's ubuntu-latest job has (for tools/ci-local.sh). Built once, then cached.
FROM rust:1-bookworm
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends ruby nodejs zip unzip python3 curl git ca-certificates >/dev/null \
 && rm -rf /var/lib/apt/lists/* && git config --global --add safe.directory '*'

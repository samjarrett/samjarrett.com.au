FROM debian

ENV ZOLA_VERSION 0.9.0
RUN set -xe && \
    apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl && \
    true

RUN set -xe && \
    cd /tmp && \
    curl -SL https://github.com/getzola/zola/releases/download/v${ZOLA_VERSION}/zola-v${ZOLA_VERSION}-x86_64-unknown-linux-gnu.tar.gz | \
      tar -zxvf - && \
    mv /tmp/zola /usr/local/bin/zola && \
    true

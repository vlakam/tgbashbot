FROM debian:stable-slim

ENV WORKDIR /app
WORKDIR $WORKDIR

RUN apt-get update && \
    apt-get install -y curl jq sqlite3 iputils-ping procps && \
    rm -rf /var/lib/{apt,dpkg,cache,log}/*

ADD . $WORKDIR

CMD bash $WORKDIR/ebashbotd.sh
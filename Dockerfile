FROM postgres:16-bullseye

ENV WALG_VERSION=2.0.1

# Install required packages
RUN apt-get update && apt-get install -y \
    wget \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install WAL-G
RUN wget "https://github.com/wal-g/wal-g/releases/download/v${WALG_VERSION}/wal-g-pg-ubuntu-20.04-amd64.tar.gz" \
    && tar -zxvf wal-g-pg-ubuntu-20.04-amd64.tar.gz \
    && mv wal-g-pg-ubuntu-20.04-amd64 /usr/local/bin/wal-g \
    && chmod +x /usr/local/bin/wal-g \
    && rm wal-g-pg-ubuntu-20.04-amd64.tar.gz

# Copy configuration files
COPY ./config/postgresql.conf /etc/postgresql/postgresql.conf
COPY ./scripts/docker-entrypoint-initdb.d /docker-entrypoint-initdb.d/

CMD ["postgres", "-c", "config_file=/etc/postgresql/postgresql.conf"]

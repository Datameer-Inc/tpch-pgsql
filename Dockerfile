# first stage
FROM python:3.8 AS builder
COPY requirements.txt .

# install dependencies to the local user directory (eg. /root/.local)
RUN pip install --user -r requirements.txt

FROM ubuntu:20.04 as final
ENV REQUIRED="postgresql-client build-essential python3 pip wget unzip vim.tiny jq"
RUN \
        apt-get update && \
        apt-get install --no-install-recommends ${REQUIRED} -y && \
        apt-get clean && rm -rf /var/lib/apt/lists/* && \
        cd /opt && \
        wget -q https://github.com/electrum/tpch-dbgen/archive/32f1c1b92d1664dba542e927d23d86ffa57aa253.zip -O tpch-dbgen.zip && \
        unzip -q tpch-dbgen.zip && mv tpch-dbgen-32f1c1b92d1664dba542e927d23d86ffa57aa253 tpch-dbgen && rm tpch-dbgen.zip
COPY --from=builder /root/.local /root/.local
COPY . /tpch-pgsql

WORKDIR /tpch-pgsql
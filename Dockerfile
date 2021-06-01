FROM ubuntu:20.04 as intermediate

ENV REQUIRED="git wget zip"

RUN apt-get update
RUN apt-get install ${REQUIRED} -y

COPY . /tpch-pgsql

RUN \
        cd /tpch-pgsql && \
        wget -q https://github.com/electrum/tpch-dbgen/archive/32f1c1b92d1664dba542e927d23d86ffa57aa253.zip -O tpch-dbgen.zip && \
        unzip -q tpch-dbgen.zip && mv tpch-dbgen-32f1c1b92d1664dba542e927d23d86ffa57aa253 tpch-dbgen && rm tpch-dbgen.zip


FROM ubuntu:20.04 as final
ENV REQUIRED="postgresql-client build-essential python3 pip"
COPY --from=intermediate /tpch-pgsql /tpch-pgsql
RUN \
        apt-get update && \
        apt-get install ${REQUIRED} -y && \
        rm -rf /var/lib/apt/lists/* && \
        cd /tpch-pgsql && \
        pip3 install -r requirements.txt

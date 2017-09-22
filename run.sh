#!/bin/bash

set -m
CONFIG_FILE="/etc/influxdb/influxdb.conf"
INFLUX_HOST="localhost"
INFLUX_API_PORT="8086"
API_URL="http://${INFLUX_HOST}:${INFLUX_API_PORT}"

if [ "${PRE_CREATE_DB}" == "**None**" ]; then
    unset PRE_CREATE_DB
fi

echo "=> Starting InfluxDB ..."
exec influxd -config=${CONFIG_FILE} &

# Pre create database on the initiation of the container
if [ -n "${PRE_CREATE_DB}" ]; then
    echo "=> About to create the following database: ${PRE_CREATE_DB}"
    if [ -f "/data/.pre_db_created" ]; then
        echo "=> Database had been created before, skipping ..."
    else
        arr=$(echo ${PRE_CREATE_DB} | tr ";" "\n")

        #wait for the startup of influxdb
        RET=1
        while [[ RET -ne 0 ]]; do
            echo "=> Waiting for confirmation of InfluxDB service startup ..."
            sleep 3
            curl -k ${API_URL}/ping 2> /dev/null
            RET=$?
        done
        echo ""

        PASS=${INFLUXDB_INIT_PWD:-root}
        if [ -n "${ADMIN_USER}" ]; then
          echo "=> Creating admin user"
          influx -host=${INFLUX_HOST} -port=${INFLUX_API_PORT} -execute="CREATE USER ${ADMIN_USER} WITH PASSWORD '${PASS}' WITH ALL PRIVILEGES"
          for x in $arr
          do
              echo "=> Creating database: ${x}"
              influx -host=${INFLUX_HOST} -port=${INFLUX_API_PORT} -username=${ADMIN_USER} -password="${PASS}" -execute="create database ${x}"
              influx -host=${INFLUX_HOST} -port=${INFLUX_API_PORT} -username=${ADMIN_USER} -password="${PASS}" -execute="grant all PRIVILEGES on ${x} to ${ADMIN_USER}"
          done
          echo ""
        else
          for x in $arr
          do
              IFS=':' read -a db <<< "${x}"
              echo "=> Creating database: ${db[0]} from \"${x}\""
              influx -host=${INFLUX_HOST} -port=${INFLUX_API_PORT} -execute="create database \"${db[0]}\""
              if [ ${#db[@]} -eq 4 ]; then
                  cmd="create retention policy \"${db[1]}\" on \"${db[0]}\" duration ${db[2]} replication 1 ${db[3]}"
                  echo "=> Creating Retention: $cmd"
                  influx -host=${INFLUX_HOST} -port=${INFLUX_API_PORT} -execute="$cmd"
             fi

          done
        fi

        touch "/data/.pre_db_created"
    fi
else
    echo "=> No database need to be pre-created"
fi

fg

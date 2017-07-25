#!/bin/bash

if [ -n "$BUILD_ID" ]; then
    export COMPOSE_PROJECT_NAME="build$BUILD_ID"
fi

# create and star the layerindex and mariadb containers
docker-compose create
docker-compose up -d

# hack to wait for db to come online
sleep 10

# Initialize the db without an admin user
docker-compose exec layerindex /bin/bash -c 'cd /opt/layerindex; python3 manage.py syncdb --noinput'

# clone repos that will be used to generate initial layerindex state
docker-compose exec layerindex /bin/bash -c 'cd /opt/; git clone --depth=1 https://github.com/WindRiver-Labs/mirror-index.git'
docker-compose exec layerindex /bin/bash -c 'cd /opt/; git clone --depth=1 https://github.com/WindRiver-Labs/wrlinux-9.git'

# copy script that transforms mirror-index into django format
docker cp ./transform_index.py "${COMPOSE_PROJECT_NAME}_layerindex_1":/opt/wrlinux-9/bin

# transform mirror-index to django format
docker-compose exec layerindex /bin/bash -c 'cd /opt/wrlinux-9/bin; ./transform_index.py --base_url https://github.com/WindRiver-Labs/wrlinux-9.git --branch WRLINUX_9_BASE --output /opt/layerindex --mirror_index /opt/mirror-index/'

# import initial layerindex state
docker-compose exec layerindex /bin/bash -c 'cd /opt/layerindex; python3 manage.py loaddata Wind_River_Developer_Layer_Index.json'

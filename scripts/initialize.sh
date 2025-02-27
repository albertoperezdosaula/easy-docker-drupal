#!/bin/bash
NC='\033[0m' # No Color
RED='\033[1;31m'
GREEN='\033[1;32m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'

# The following variable is used from other script "create-docker-project.sh". This scripts runs intialize.sh passing the PROJECT_NAME variable.
# Please see create-docker-project.sh here: https://github.com/albertoperezdosaula/scripts/blob/main/create-docker-project.sh
PROJECT_NAME_VAR=$1

#Get script folder depends if this script is runned from create-docker-project.sh or not.
if [[ ! "${PROJECT_NAME_VAR}" == "" ]]; then
  WORK_DIR=$( cd "$( dirname "$0" )" && pwd )
else
  WORK_DIR=$( cd "$( dirname "$0" )" && pwd )/..
fi

echo -e "${YELLOW}#########################################################################################${NC}\r"
echo -e "${YELLOW}############################### EASY DOCKER CONFIGURATION ###############################${NC}\r"
echo -e "${YELLOW}#########################################################################################${NC}\r"
printf '\n'

if [[ "${PROJECT_NAME_VAR}" == "" ]]; then
  printf "Please, input the name of the project (without spaces): "
  read PROJECT_NAME
fi

printf "Please, select database storage (mariadb/postgres) [mariadb]: "
read input_db
DATABASE_ENGINE=${input_db:=mariadb}


printf "Please, select webserver engine (apache/nginx) [apache]: "
read input_ws
WEBSERVER_ENGINE=${input_ws:=apache}

printf "Please, select search engine (solr/elastic) [solr]: "
read input_se
SEARCH_ENGINE=${input_se:=solr}

printf "Mailhog enabled (yes/no) [yes]: "
read input_mh
MAILHOG_ENGINE=${input_mh:=yes}


printf "Redis enabled (yes/no) [yes]: "
read input_rd
REDIS_ENGINE=${input_rd:=yes}

printf "Launch docker (yes/no) [yes]: "
read input_ld
LAUNCH_DOCKER=${input_ld:=yes}

cat scripts/templates-dc/edd-dc.yml > docker-compose.yml
cat scripts/templates-dc/edd-dc-${DATABASE_ENGINE}.yml >> docker-compose.yml
cat scripts/templates-dc/edd-dc-${WEBSERVER_ENGINE}.yml >> docker-compose.yml
cat scripts/templates-dc/edd-dc-${SEARCH_ENGINE}.yml >> docker-compose.yml

if [ ${MAILHOG_ENGINE} == 'yes' ]
then
  cat scripts/templates-dc/edd-dc-mailhog.yml >> docker-compose.yml
fi

if [ ${REDIS_ENGINE} == 'yes' ]
then
  cat scripts/templates-dc/edd-dc-redis.yml >> docker-compose.yml
fi

printf "${GREEN}Configuring environment...${NC}\n"
printf "  Modifying environment name...${NC}\n"
sed -i "s/PROJECT_NAME=vm/PROJECT_NAME=${PROJECT_NAME}/g" ${WORK_DIR}/.env

echo -e "${YELLOW}#########################################################################################${NC}\r"
echo -e "${YELLOW}################################### SSH CONFIGURATION ###################################${NC}\r"
echo -e "${YELLOW}#########################################################################################${NC}\r"
printf '\n'

#Check if exists certificates to generate certificates for environment
FILE=~/.ssh/id_rsa
if [ ! -f "${FILE}" ]
then
    printf "  Generating SSH keys...${NC}\n"
    ssh-keygen -t rsa -f ~/.ssh/id_rsa -q -P ""
fi

#Copy certificates from local into environment
printf "  Copying SSH keys...${NC}\n"
mkdir -p ${WORK_DIR}/conf/ssh
cp ~/.ssh/id_rsa ${WORK_DIR}/conf/ssh/id_rsa
cp ~/.ssh/id_rsa.pub ${WORK_DIR}/conf/ssh/id_rsa.pub

#Generate certificate for HTTPS
printf "  Generating SSL certificate for apache...${NC}\n"
mkdir -p ${WORK_DIR}/conf/ssl
openssl req -x509 -new -newkey rsa:4096 -nodes -days 2048 \
    -keyout ${WORK_DIR}/conf/ssl/localhost.key -out ${WORK_DIR}/conf/ssl/localhost.crt \
    -subj "/C=ES/O=DEX/OU=CEPPHP/CN=${PROJECT_NAME}.vm" > /dev/null 2>&1

echo -e "${YELLOW}#########################################################################################${NC}\r"
echo -e "${YELLOW}############################### VIRTUALHOST CONFIGURATION ###############################${NC}\r"
echo -e "${YELLOW}#########################################################################################${NC}\r"
printf '\n'

printf "  Modifying Virtualhost...${NC}\n"
if [ ${WEBSERVER_ENGINE} == 'nginx' ]
then
  sed -i "s/\/usr\/share\/nginx\/html\/your.docroot.project\/web;/\/usr\/share\/nginx\/html\/${PROJECT_NAME}\/web;/g" ./conf/nginx/nginx.d/default.conf
  sed -i "s/server_name your.domain/server_name ${PROJECT_NAME}/g" ${WORK_DIR}/conf/nginx/nginx.d/default.conf
else
  sed -i "s/your.domain/${PROJECT_NAME}/g" ${WORK_DIR}/conf/apache/virtualhost.conf
  sed -i "s/your.docroot.project/${PROJECT_NAME}/g" ${WORK_DIR}/conf/apache/virtualhost.conf
fi

# Change alias_url in /etc/hosts.
sudo bash -c "echo 127.0.0.1 ${PROJECT_NAME}.vm >> /etc/hosts"

printf "${GREEN}Environment configured...${NC}\n"
printf "  Virtualhost configuration...\n"
printf "   * Domain configured as ${PURPLE}https://${PROJECT_NAME}.vm${NC}\n"
printf "   * Adding domain to ${PURPLE}/etc/hosts${NC}\n"
if [ ${WEBSERVER_ENGINE} == 'nginx' ]
then
  printf "   * Document root configured in ${PURPLE}/usr/share/nginx/html/${PROJECT_NAME}/web${NC}\n"
else
  printf "   * Document root configured in ${PURPLE}/var/www/html/${PROJECT_NAME}/web${NC}\n"
fi
printf "\n"

if [ ${MAILHOG_ENGINE} == 'yes' ]
then
  printf "${GREEN}Launch environment...${NC}\n"
  docker-compose up -d --build
fi

#!/usr/bin/env bash

# Description: Install and manage a ChatORG installation.
# OS: Ubuntu 20.04 LTS
# Script Version: 2.2.0
# Run this script as root

set -eu -o errexit -o pipefail -o noclobber -o nounset

# -allow a command to fail with !’s side effect on errexit
# -use return value from ${PIPESTATUS[0]}, because ! hosed $?
! getopt --test > /dev/null 
if [[ ${PIPESTATUS[0]} -ne 4 ]]; then
    echo '`getopt --test` failed in this environment.'
    exit 1
fi

# Global variables
# option --output/-o requires 1 argument
LONGOPTS=console,debug,help,install,Install:,logs:,restart,ssl,upgrade,webserver,version
OPTIONS=cdhiI:l:rsuwv
CWCTL_VERSION="2.2.0"
pg_pass=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 15 ; echo '')

# if user does not specify an option
if [ "$#" -eq 0 ]; then
  echo "No options specified. Use --help to learn more."
  exit 1
fi

# -regarding ! and PIPESTATUS see above
# -temporarily store output to be able to check for errors
# -activate quoting/enhanced mode (e.g. by writing out “--options”)
# -pass arguments only via   -- "$@"   to separate them correctly
! PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    # e.g. return value is 1
    #  then getopt has complained about wrong arguments to stdout
    exit 2
fi
# read getopt’s output this way to handle the quoting right:
eval set -- "$PARSED"

c=n d=n h=n i=n I=n l=n r=n s=n u=n w=n v=n BRANCH=master SERVICE=web
# Iterate options in order and nicely split until we see --
while true; do
    case "$1" in
        -c|--console)
            c=y
            break
            ;;
        -d|--debug)
            d=y
            shift
            ;;
        -h|--help)
            h=y
            break
            ;;
        -i|--install)
            i=y
            BRANCH="master"
            break
            ;;
       -I|--Install)
            I=y
            BRANCH="$2"
            break
            ;;
        -l|--logs)
            l=y
            SERVICE="$2"
            break
            ;;
        -r|--restart)
            r=y
            break
            ;;
        -s|--ssl)
            s=y
            shift
            ;;
        -u|--upgrade)
            u=y
            break
            ;;
        -w|--webserver)
            w=y
            shift
            ;;
        -v|--version)
            v=y
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Invalid option(s) specified. Use help(-h) to learn more."
            exit 3
            ;;
    esac
done

# log if debug flag set
if [ "$d" == "y" ]; then
  echo "console: $c, debug: $d, help: $h, install: $i, Install: $I, BRANCH: $BRANCH, \
  logs: $l, SERVICE: $SERVICE, ssl: $s, upgrade: $u, webserver: $w"
fi

# exit if script is not run as root
if [ "$(id -u)" -ne 0 ]; then
  echo 'This needs to be run as root.' >&2
  exit 1
fi

trap exit_handler EXIT

##############################################################################
# Invoked upon EXIT signal from bash
# Upon non-zero exit, notifies the user to check log file.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   None
##############################################################################
function exit_handler() {
  if [ "$?" -ne 0 ] && [ "$u" == "n" ]; then
   echo -en "\nSome error has occured. Check '/var/log/chatorg-setup.log' for details.\n"
   exit 1
  fi
}

##############################################################################
# Read user input related to domain setup
# Globals:
#   domain_name
#   le_email
# Arguments:
#   None
# Outputs:
#   None
##############################################################################
function get_domain_info() {
  read -rp 'Enter the domain/subdomain for ChatORG (e.g., chatorg.domain.com): ' domain_name
  read -rp 'Enter an email address for LetsEncrypt to send reminders when your SSL certificate is up for renewal: ' le_email
  cat << EOF

This script will generate SSL certificates via LetsEncrypt and
serve ChatORG at https://$domain_name.
Proceed further once you have pointed your DNS to the IP of the instance.

EOF
  read -rp 'Do you wish to proceed? (yes or no): ' exit_true
  if [ "$exit_true" == "no" ]; then
    exit 1
  fi
}

##############################################################################
# Install common dependencies
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   None
##############################################################################
function install_dependencies() {
  apt-get update && apt-get upgrade -y
  apt-get install -y curl
  curl -sL https://deb.nodesource.com/setup_16.x | bash -
  curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -
  echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list
  apt-get update

  apt-get install -y \
      git software-properties-common imagemagick libpq-dev \
      libxml2-dev libxslt1-dev file g++ gcc autoconf build-essential \
      libssl-dev libyaml-dev libreadline-dev gnupg2 \
      postgresql-client redis-tools \
      nodejs yarn patch ruby-dev zlib1g-dev liblzma-dev \
      libgmp-dev libncurses5-dev libffi-dev libgdbm6 libgdbm-dev sudo

  apt-get update
  apt-get upgrade
  curl -fsSL https://get.docker.com -o get-docker.sh
  sudo sh get-docker.sh
  apt install docker-compose-plugin

  # # Add Docker's official GPG key:
  # apt-get install -y ca-certificates
  # install -m 0755 -d /etc/apt/keyrings
  # curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  # chmod a+r /etc/apt/keyrings/docker.asc

  # # Add the repository to Apt sources:
  # echo \
  #   "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  #   $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  #   tee /etc/apt/sources.list.d/docker.list > /dev/null
  # apt-get update

  # # Install Docker
  # apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # # install docker-compose
  # curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  # chmod +x /usr/local/bin/docker-compose
}

##############################################################################
# Install postgres and redis
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   None
##############################################################################
function install_databases() {
  apt-get install -y postgresql postgresql-contrib
}

##############################################################################
# Install nginx and cerbot for LetsEncrypt
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   None
##############################################################################
function install_webserver() {
  apt-get install -y nginx nginx-full certbot python3-certbot-nginx
}

##############################################################################
# Create chatorg linux user
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   None
##############################################################################
function create_cw_user() {
  if ! id -u "chatorg"; then
    adduser --disabled-login --gecos "" chatorg
  fi
}

##############################################################################
# Install rvm(ruby version manager)
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   None
##############################################################################
function configure_rvm() {
  create_cw_user

  gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB
  gpg2 --keyserver hkp://keyserver.ubuntu.com --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB
  curl -sSL https://get.rvm.io | bash -s stable
  adduser chatorg rvm
}

##############################################################################
# Save the pgpass used to setup postgres
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   None
##############################################################################
function save_pgpass() {
  mkdir -p /opt/chatorg/config
  file="/opt/chatorg/config/.pg_pass"
  if ! test -f "$file"; then
    echo $pg_pass > /opt/chatorg/config/.pg_pass
  fi
}

# function save_pgpass_for_crm() {
#   mkdir -p /opt/crmorg/config
#   file="/opt/crmorg/config/.pg_pass"
#   if ! test -f "$file"; then
#     echo $pg_pass > /opt/crmorg/config/.pg_pass
#   fi
# }

##############################################################################
# Get the pgpass used to setup postgres if installation fails midway
# and needs to be re-run
# Globals:
#   pg_pass
# Arguments:
#   None
# Outputs:
#   None
##############################################################################
function get_pgpass() {
  file="/opt/chatorg/config/.pg_pass"
  if test -f "$file"; then
    pg_pass=$(cat $file)
  fi

}
# function get_pgpass_for_crm() {
#   file="/opt/crmorg/config/.pg_pass"
#   if test -f "$file"; then
#     pg_pass=$(cat $file)
#   fi

# }

##############################################################################
# Configure postgres to create chatorg db user.
# Enable postgres and redis systemd services.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   None
##############################################################################
function configure_db() {
  save_pgpass
  get_pgpass
  
  sudo -i -u postgres psql << EOF
    \set pass `echo $pg_pass`
    CREATE USER chatorg CREATEDB;
    ALTER USER chatorg PASSWORD :'pass';
    ALTER ROLE chatorg SUPERUSER;
    CREATE DATABASE crm_production OWNER chatorg;
    UPDATE pg_database SET datistemplate = FALSE WHERE datname = 'template1';
    DROP DATABASE template1;
    CREATE DATABASE template1 WITH TEMPLATE = template0 ENCODING = 'UNICODE';
    UPDATE pg_database SET datistemplate = TRUE WHERE datname = 'template1';
    \c template1
    VACUUM FREEZE;
EOF

  # systemctl enable redis-server.service
  systemctl enable postgresql
}

##############################################################################
# Install ChatORG
# This includes setting up ruby, cloning repo and installing dependencies.
# Globals:
#   pg_pass
# Arguments:
#   None
# Outputs:
#   None
##############################################################################
function setup_chatorg() {
  local secret=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 63 ; echo '')
  local RAILS_ENV=production
  local REGISTRY_URL="https://index.docker.io/v1/"
  local USERNAME="toantran2409@gmail.com"
  local PASSWORD="1jahdi@#jdskljk33A"
  get_pgpass

  sed -i -e '/POSTGRES_HOST/ s/=.*/=localhost/' docker-compose.yml
  sed -i -e '/POSTGRES_USERNAME/ s/=.*/=chatorg/' docker-compose.yml
  sed -i -e "/POSTGRES_PASSWORD/ s/=.*/=$pg_pass/" docker-compose.yml
  sed -i -e "/FRONTEND_URL/ s/=.*/=https://$domain_name/" docker-compose.yml

  sed -i -e "/DB_HOST/ s/=.*/=localhost/" docker-compose.yml
  sed -i -e '/DB_PORT/ s/=.*/=5432/' docker-compose.yml
  sed -i -e '/DB_USER/ s/=.*/=chatorg/' docker-compose.yml
  sed -i -e "/DB_PASSWORD/ s/=.*/=$pg_pass/" docker-compose.yml
  sed -i -e '/DB_NAME/ s/=.*/=crm_production/' docker-compose.yml

  sed -i -e '/DB_CHAT_HOST/ s/=.*/=localhost/' docker-compose.yml
  sed -i -e '/DB_CHAT_PORT/ s/=.*/=5432/' docker-compose.yml
  sed -i -e '/DB_CHAT_USER/ s/=.*/=chatorg/' docker-compose.yml
  sed -i -e "/DB_CHAT_PASSWORD/ s/=.*/=$pg_pass/" docker-compose.yml
  sed -i -e "/DB_CHAT_NAME/ s/=.*/=chat_production/" docker-compose.yml

  sed -i -e "/VITE_APP_URL/ s/=.*/=https://$domain_name/" docker-compose.yml
  sed -i -e "/VITE_APP_CHAT_URL/ s/=.*/=https://$domain_name/" docker-compose.yml
  sed -i -e "/VITE_CHAT_WEBSOCKET_URL/ s/=.*/=wss://$domain_name/" docker-compose.yml

  docker login $REGISTRY_URL -u $USERNAME -p $PASSWORD
  docker pull toantran249/chat-org:latest
  docker pull toantran249/crm-be-org:latest
  docker pull toantran249/crm-fe-org:latest
  docker logout $REGISTRY_URL
  docker compose -f docker-compose.yml up -d sidekiq
  docker compose -f docker-compose.yml up -d rails
  docker compose -f docker-compose.yml up -d crm-be
  docker compose -f docker-compose.yml up -d crm-fe
}

##############################################################################
# Run database migrations.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   None
##############################################################################
function run_db_migrations(){
  docker compose run --rm rails bundle exec rails db:chatorg_prepare
}

##############################################################################
# Setup ChatORG systemd services and cwctl CLI
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   None
##############################################################################
function configure_systemd_services() {
  cp /home/chatorg/chatorg/deployment/chatorg-web.1.service /etc/systemd/system/chatorg-web.1.service
  cp /home/chatorg/chatorg/deployment/chatorg-worker.1.service /etc/systemd/system/chatorg-worker.1.service
  cp /home/chatorg/chatorg/deployment/chatorg.target /etc/systemd/system/chatorg.target

  cp /home/chatorg/chatorg/deployment/chatorg /etc/sudoers.d/chatorg
  cp /home/chatorg/chatorg/deployment/setup_20.04.sh /usr/local/bin/cwctl
  chmod +x /usr/local/bin/cwctl

  systemctl enable chatorg.target
  systemctl start chatorg.target
}

##############################################################################
# Fetch and install SSL certificates from LetsEncrypt
# Modify the nginx config and restart nginx.
# Also modifies FRONTEND_URL in .env file.
# Globals:
#   None
# Arguments:
#   domain_name
#   le_email
# Outputs:
#   None
##############################################################################
function setup_ssl() {
  if [ "$d" == "y" ]; then
    echo "debug: setting up ssl"
    echo "debug: domain: $domain_name"
    echo "debug: letsencrypt email: $le_email"
  fi
  curl https://ssl-config.mozilla.org/ffdhe4096.txt >> /etc/ssl/dhparam
  wget https://raw.githubusercontent.com/toantran249/crm-chat/main/nginx_chatorg.conf
  cp nginx_chatorg.conf /etc/nginx/sites-available/nginx_chatorg.conf
  certbot certonly --non-interactive --agree-tos --nginx -m "$le_email" -d "$domain_name"
  sed -i "s/chatorg.domain.com/$domain_name/g" /etc/nginx/sites-available/nginx_chatorg.conf
  ln -s /etc/nginx/sites-available/nginx_chatorg.conf /etc/nginx/sites-enabled/nginx_chatorg.conf
  systemctl restart nginx
  # systemctl restart chatorg.target
}

##############################################################################
# Setup logging
# Globals:
#   LOG_FILE
# Arguments:
#   None
# Outputs:
#   None
##############################################################################
function setup_logging() {
  touch /var/log/chatorg-setup.log
  LOG_FILE="/var/log/chatorg-setup.log"
}

function ssl_success_message() {
    cat << EOF

***************************************************************************
Woot! Woot!! ChatORG server installation is complete.
The server will be accessible at https://$domain_name

Join the community at https://chatorg.com/community?utm_source=cwctl
***************************************************************************

EOF
}

function cwctl_message() {
  echo $'\U0001F680 Try out the all new ChatORG CLI tool to manage your installation.'
  echo $'\U0001F680 Type "cwctl --help" to learn more.'
}


##############################################################################
# This function handles the installation(-i/--install)
# Globals:
#   CW_VERSION
# Arguments:
#   None
# Outputs:
#   None
##############################################################################
function get_cw_version() {
  CW_VERSION=$(curl -s https://app.chatorg.com/api | python3 -c 'import sys,json;data=json.loads(sys.stdin.read()); print(data["version"])')
}

##############################################################################
# This function handles the installation(-i/--install)
# Globals:
#   configure_webserver
#   install_pg_redis
# Arguments:
#   None
# Outputs:
#   None
##############################################################################
function install() {
  get_cw_version
  cat << EOF

***************************************************************************
              ChatORG Installation (v$CW_VERSION)
***************************************************************************

For more verbose logs, open up a second terminal and follow along using,
'tail -f /var/log/chatorg-setup.log'.

EOF

  sleep 3
  read -rp 'Would you like to configure a domain and SSL for ChatORG?(yes or no): ' configure_webserver

  if [ "$configure_webserver" == "yes" ]; then
    get_domain_info
  fi

  echo -en "\n"
  read -rp 'Would you like to install Postgres and Redis? (Answer no if you plan to use external services): ' install_pg_redis

  echo -en "\n➥ 1/9 Installing dependencies. This takes a while.\n"
  install_dependencies &>> "${LOG_FILE}"

  if [ "$install_pg_redis" != "no" ]; then
    echo "➥ 2/9 Installing databases."
    install_databases &>> "${LOG_FILE}"
  else
    echo "➥ 2/9 Skipping Postgres installation."
  fi

  if [ "$configure_webserver" == "yes" ]; then
    echo "➥ 3/9 Installing webserver."
    install_webserver &>> "${LOG_FILE}"
  else
    echo "➥ 3/9 Skipping webserver installation."
  fi

  echo "➥ 4/9 Setting up Ruby"
  configure_rvm &>> "${LOG_FILE}"

  if [ "$install_pg_redis" != "no" ]; then
    echo "➥ 5/9 Setting up the database."
    configure_db &>> "${LOG_FILE}"
  else
    echo "➥ 5/9 Skipping database setup."
  fi

  echo "➥ 6/9 Installing ChatORG. This takes a long while."
  setup_chatorg &>> "${LOG_FILE}"

  if [ "$install_pg_redis" != "no" ]; then
    echo "➥ 7/9 Running database migrations."
    run_db_migrations &>> "${LOG_FILE}"
  else
    echo "➥ 7/9 Skipping database migrations."
  fi

  echo "➥ 8/9 Setting up systemd services."
  # configure_systemd_services &>> "${LOG_FILE}"

  public_ip=$(curl http://checkip.amazonaws.com -s)

  if [ "$configure_webserver" != "yes" ]
  then
    cat << EOF
➥ 9/9 Skipping SSL/TLS setup.

***************************************************************************
Woot! Woot!! ChatORG server installation is complete.
The server will be accessible at http://$public_ip:3000

To configure a domain and SSL certificate, follow the guide at
https://www.chatorg.com/docs/deployment/deploy-chatorg-in-linux-vm?utm_source=cwctl

Join the community at https://chatorg.com/community?utm_source=cwctl
***************************************************************************

EOF
  cwctl_message
  else
    echo "➥ 9/9 Setting up SSL/TLS."
    setup_ssl &>> "${LOG_FILE}"
    ssl_success_message
    cwctl_message
  fi

  if [ "$install_pg_redis" == "no" ]
  then
cat <<EOF

***************************************************************************
The database migrations had not run as Postgres and Redis were not installed
as part of the installation process. After modifying the environment
variables (in the .env file) with your external database credentials, run
the database migrations using the below command.
'RAILS_ENV=production bundle exec rails db:chatorg_prepare'.
***************************************************************************

EOF
  cwctl_message
  fi

exit 0

}

##############################################################################
# Access ruby console (-c/--console)
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   None
##############################################################################
function get_console() {
  sudo -i -u chatorg bash -c " cd chatorg && RAILS_ENV=production bundle exec rails c"
}

##############################################################################
# Prints the help message (-c/--console)
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   None
##############################################################################
function help() {

  cat <<EOF
Usage: cwctl [OPTION]...
Install and manage your ChatORG installation.

Example: cwctl -i master
Example: cwctl -l web
Example: cwctl --logs worker
Example: cwctl --upgrade
Example: cwctl -c

Installation/Upgrade:
  -i, --install             Install the latest stable version of ChatORG
  -I                        Install ChatORG from a git branch
  -u, --upgrade             Upgrade ChatORG to the latest stable version
  -s, --ssl                 Fetch and install SSL certificates using LetsEncrypt
  -w, --webserver           Install and configure Nginx webserver with SSL

Management:
  -c, --console             Open ruby console
  -l, --logs                View logs from ChatORG. Supported values include web/worker.
  -r, --restart             Restart ChatORG server
  
Miscellaneous:
  -d, --debug               Show debug messages
  -v, --version             Display version information
  -h, --help                Display this help text

Exit status:
Returns 0 if successful; non-zero otherwise.

Report bugs at https://github.com/chatorg/chatorg/issues
Get help, https://chatorg.com/community?utm_source=cwctl

EOF
}

##############################################################################
# Get ChatORG web/worker logs (-l/--logs)
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   None
##############################################################################
function get_logs() {
  if [ "$SERVICE" == "worker" ]; then
    journalctl -u chatorg-worker.1.service -f
  fi
  if [ "$SERVICE" == "web" ]; then
    journalctl -u chatorg-web.1.service -f
  fi
}

##############################################################################
# Setup SSL (-s/--ssl)
# Installs nginx if not available.
# Globals:
#   domain_name
#   le_email
# Arguments:
#   None
# Outputs:
#   None
##############################################################################
function ssl() {
   if [ "$d" == "y" ]; then
     echo "Setting up ssl"
   fi
   get_domain_info
   if ! systemctl -q is-active nginx; then
    install_webserver
   fi
   setup_ssl
   ssl_success_message
}

##############################################################################
# Abort upgrade if custom code changes detected(-u/--upgrade)
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   None
##############################################################################
function upgrade_prereq() {
  sudo -i -u chatorg << "EOF"
  cd chatorg
  git update-index --refresh
  git diff-index --quiet HEAD --
  if [ "$?" -eq 1 ]; then
    echo "Custom code changes detected. Aborting update."
    echo "Please proceed to update manually."
    exit 1
  fi
EOF
}

##############################################################################
# Upgrade an existing installation to latest stable version(-u/--upgrade)
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   None
##############################################################################
function upgrade() {
  get_cw_version
  echo "Upgrading ChatORG to v$CW_VERSION"
  sleep 3
  upgrade_prereq
  sudo -i -u chatorg << "EOF"

  # Navigate to the ChatORG directory
  cd chatorg

  # Pull the latest version of the master branch
  git checkout master && git pull

  # Ensure the ruby version is upto date
  # Parse the latest ruby version
  latest_ruby_version="$(cat '.ruby-version')"
  rvm install "ruby-$latest_ruby_version"
  rvm use "$latest_ruby_version" --default

  # Update dependencies
  bundle
  yarn

  # Recompile the assets
  rake assets:precompile RAILS_ENV=production

  # Migrate the database schema
  RAILS_ENV=production bundle exec rake db:migrate

EOF

  # Copy the updated targets
  cp /home/chatorg/chatorg/deployment/chatorg-web.1.service /etc/systemd/system/chatorg-web.1.service
  cp /home/chatorg/chatorg/deployment/chatorg-worker.1.service /etc/systemd/system/chatorg-worker.1.service
  cp /home/chatorg/chatorg/deployment/chatorg.target /etc/systemd/system/chatorg.target

  cp /home/chatorg/chatorg/deployment/chatorg /etc/sudoers.d/chatorg
  # TODO:(@vn) handle cwctl updates

  systemctl daemon-reload

  # Restart the chatorg server
  systemctl restart chatorg.target

}

##############################################################################
# Restart ChatORG server (-r/--restart)
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   None
##############################################################################
function restart() {
  systemctl restart chatorg.target
  systemctl status chatorg.target
}

##############################################################################
# Install nginx and setup SSL (-w/--webserver)
# Globals:
#   domain_name
#   le_email
# Arguments:
#   None
# Outputs:
#   None
##############################################################################
function webserver() {
  if [ "$d" == "y" ]; then
     echo "Installing nginx"
  fi
  ssl
  #TODO(@vn): allow installing nginx only without SSL
}

##############################################################################
# Print cwctl version (-v/--version)
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   None
##############################################################################
function version() {
  echo "cwctl v$CWCTL_VERSION alpha build"
}

##############################################################################
# main function that handles the control flow
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   None
##############################################################################
function main() {
  setup_logging

  if [ "$c" == "y" ]; then
    get_console
  fi
  
  if [ "$h" == "y" ]; then
    help
  fi

  if [ "$i" == "y" ] || [ "$I" == "y" ]; then
    install
  fi

  if [ "$l" == "y" ]; then
    get_logs
  fi

  if [ "$r" == "y" ]; then
    restart
  fi
  
  if [ "$s" == "y" ]; then
    ssl
  fi

  if [ "$u" == "y" ]; then
    upgrade
  fi

  if [ "$w" == "y" ]; then
    webserver
  fi

  if [ "$v" == "y" ]; then
    version
  fi

}

main "$@"

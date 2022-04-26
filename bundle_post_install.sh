#!/bin/bash

set -e
set -o pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

if [ -z "$CONFIG_NAME" ]
then
  CONFIG_NAME=$1
fi

if [ -z "$CONFIG_NAME" ]
then
    CONFIG_NAME=default
fi

echo "Using configuration name suffix $CONFIG_NAME"

# Create user and group 'yajudge' in case if not exists

if [ -z "$YAJUDGE_USER" ]
then
    YAJUDGE_USER=yajudge
fi

if [ ! $(id -u $YAJUDGE_USER) ]
then
    useradd -rmU -s /usr/sbin/nologin -d $SCRIPT_DIR $YAJUDGE_USER
fi

echo "Created user $YAJUDGE_USER and group $YAJUDGE_USER"

# Initialize directories variables

if [ -z "$YAJUDGE_DIR" ]
then
    YAJUDGE_DIR="$SCRIPT_DIR"
fi

echo "Yajudge installation directory is $SCRIPT_DIR"

if [ -z "$LOG_DIR" ]
then
    LOG_DIR="$YAJUDGE_DIR/log"
fi

echo "Will use $LOG_DIR as directory for log files"

if [ -z "$PID_DIR" ]
then
    PID_DIR="$YAJUDGE_DIR/pid"
fi

echo "Will use $PID_DIR as directory for PID files"

if [ -z "$WORK_DIR" ]
then
    WORK_DIR="$YAJUDGE_DIR/work"
fi

echo "Will use $WORK_DIR as directory for grader submissions"

if [ -z "$CACHE_DIR" ]
then
    CACHE_DIR="$YAJUDGE_DIR/cache"
fi

echo "Will use $CACHE_DIR as directory for grader's courses cache"

if [ -z "$COURSES_DIR" ]
then
    COURSES_DIR="$YAJUDGE_DIR/courses"
fi

echo "Will use $COURSES_DIR as directory for courses root"

if [ -z "$PROBLEMS_DIR" ]
then
    PROBLEMS_DIR="$YAJUDGE_DIR/problems"
fi

echo "Will use $PROBLEMS_DIR as directory for problems root"

if [ -z "$SYSTEM_DIR" ]
then
    SYSTEM_DIR="$YAJUDGE_DIR/system"
fi

echo "Will use $SYSTEM_DIR as directory for grader's isolated base operating system files"

if [ -z "$CONF_DIR" ]
then
    CONF_DIR=/etc/yajudge
fi

echo "Will use $CONF_DIR to make configuration files"

if [ -z "$SYSTEMD_DIR" ]
then
    SYSTEMD_DIR=/etc/systemd/system
fi

echo "Will use $SYSTEMD_DIR to make systemd units"

if [ -z "$BIN_DIR" ]
then
    BIN_DIR="$YAJUDGE_DIR/bin"
fi

echo "Yajudge executables located in $BIN_DIR"

if [ -z "$WEB_DIR" ]
then
    WEB_DIR="$YAJUDGE_DIR/web"
fi

echo "Yajudge web-exposed content located in $WEB_DIR"

mkdir -p $CONF_DIR
mkdir -p $CONF_DIR/sites-available
mkdir -p $CONF_DIR/sites-enabled

dirs=("$LOG_DIR" "$PID_DIR" "$CACHE_DIR" "$COURSES_DIR" "$PROBLEMS_DIR" "$WORK_DIR" "$SYSTEM_DIR")
for d in ${dirs[*]}
do
    mkdir -p $d
    chown $YAJUDGE_USER:$YAJUDGE_USER $d
    chmod g+w $d
    echo "Directory $d now owned by user $YAJUDGE_USER and writable by group $YAJUDGE_USER"
done


# Prepare text replacements for config files and systemd units

function screen_slash() {
    echo $1 | sed -r s'/\//\\\//g'
}

repl="       s/@LOGS_DIRECTORY/$(screen_slash $LOG_DIR)/g"
repl="$repl; s/@RUNTIME_DIRECTORY/$(screen_slash $PID_DIR)/g"
repl="$repl; s/@CONFIGURATION_DIRECTORY/$(screen_slash $CONF_DIR)/g"
repl="$repl; s/@STATE_DIRECTORY/$(screen_slash $YAJUDGE_DIR)/g"
repl="$repl; s/@BIN_DIR/$(screen_slash $BIN_DIR)/g"
repl="$repl; s/@WEB_DIRECTORY/$(screen_slash $WEB_DIR)/g"
repl="$repl; s/@PROBLEMS_DIR/$(screen_slash $PROBLEMS_DIR)/g"
repl="$repl; s/@COURSES_DIR/$(screen_slash $COURSES_DIR)/g"
repl="$repl; s/@WORK_DIR/$(screen_slash $WORK_DIR)/g"
repl="$repl; s/@SYSTEM_DIR/$(screen_slash $SYSTEM_DIR)/g"
repl="$repl; s/@CACHE_DIRECTORY/$(screen_slash $CACHE_DIR)/g"
repl="$repl; s/@YAJUDGE_USER/$(screen_slash $YAJUDGE_USER)/g"
repl="$repl; s/@CONFIG_NAME/$(screen_slash $CONFIG_NAME)/g"


# Check for existing config files not to replace

if [ -f $CONF_DIR/master-$CONFIG_NAME.yaml ]
then
    MASTER_CONF=$CONF_DIR/master-$CONFIG_NAME.new.yaml
    echo "Found existing master configuration"
else
    MASTER_CONF=$CONF_DIR/master-$CONFIG_NAME.yaml
fi

echo "Master configuration will be created in $MASTER_CONF"

if [ -f $CONF_DIR/grader-$CONFIG_NAME.yaml ]
then
    GRADER_CONF=$CONF_DIR/grader-$CONFIG_NAME.new.yaml
    echo "Found existing grader configuration"
else
    GRADER_CONF=$CONF_DIR/grader-$CONFIG_NAME.yaml
fi

echo "Grader configuration will be created in $GRADER_CONF"

if [ -f $CONF_DIR/grpcwebserver.yaml ]
then
  WEB_SERVER_CONF=$CONF_DIR/grpcwebserver.yaml.new
  echo "Found existing grpcwebserver configuration"
else
  WEB_SERVER_CONF=$CONF_DIR/grpcwebserver.yaml
fi

echo "GrpcWebServer configuration will be created in $WEB_SERVER_CONF"

if [ -f $CONF_DIR/sites-available/$CONFIG_NAME.yaml ]
then
  WEB_SITE_CONF=$CONF_DIR/sites-available/$CONFIG_NAME.yaml.new
  echo "Found existing grpcwebserver site configuration"
else
  WEB_SITE_CONF=$CONF_DIR/sites-available/$CONFIG_NAME.yaml
  WEB_SITE_LINK=$CONF_DIR/sites-enabled/$CONFIG_NAME.yaml
fi

echo "GrpcWebServer site configuration will be created in $WEB_SITE_CONF"

# Create default database password file if not exists

if [ ! -f $CONF_DIR/database-password.txt ]
then
    echo 'yajudge' > $CONF_DIR/database-password.txt
    chown $YAJUDGE_USER:$YAJUDGE_USER $CONF_DIR/database-password.txt
    chmod 0440 $CONF_DIR/database-password.txt
    echo "Created database password 'yajudge' in $CONF_DIR/database-password.txt"
else
    echo "Found existing database password file in $CONF_DIR/database-password.txt"
fi


# Create private token file if not exists

if [ ! -f $CONF_DIR/private-token.txt ]
then
    head -c 1024 /dev/random | md5sum | cut -d ' ' -f 1 > $CONF_DIR/private-token.txt
    chown $YAJUDGE_USER:$YAJUDGE_USER $CONF_DIR/private-token.txt
    chmod 0440 $CONF_DIR/private-token.txt
    echo "Created random private token in $CONF_DIR/private-token.txt"
else
    echo "Found existing private token file in $CONF_DIR/private-token.txt"
fi


# Preprocess and create config files

sed -E "$repl" conf/grader.in.yaml > $GRADER_CONF
echo "Created file $GRADER_CONF"
sed -E "$repl" conf/master.in.yaml > $MASTER_CONF
echo "Created file $MASTER_CONF"
sed -E "$repl" conf/grpcwebserver.in.yaml > $WEB_SERVER_CONF
echo "Created file $WEB_SERVER_CONF"
sed -E "$repl" conf/site@.in.yaml > $WEB_SITE_CONF
echo "Created file $WEB_SITE_CONF"

# Enable web config

if [ "$WEB_SITE_LINK" ]
then
  if [ ! -L "$WEB_SITE_LINK" ]
  then
    ln -f -s -T "../sites-available/$CONFIG_NAME.yaml" $WEB_SITE_LINK
    echo "$WEB_SITE_CONF symlinked to $WEB_SITE_LINK"
  fi
fi


# Preprocess and create systemd files

cat systemd/yajudge-grader.slice > $SYSTEMD_DIR/yajudge-grader.slice
echo "Created file $SYSTEMD_DIR/yajudge-grader.slice"

sed -E "$repl" systemd/yajudge-grader-prepare.in.service > $SYSTEMD_DIR/yajudge-grader-prepare.service
echo "Created file $SYSTEMD_DIR/yajudge-grader-prepare.service"

sed -E "$repl" systemd/yajudge-grader@.in.service > $SYSTEMD_DIR/yajudge-grader@.service
echo "Created file $SYSTEMD_DIR/yajudge-grader@.service"

sed -E "$repl" systemd/yajudge-master@.in.service > $SYSTEMD_DIR/yajudge-master@.service
echo "Created file $SYSTEMD_DIR/yajudge-master@.service"

sed -E "$repl" systemd/yajudge-grpcwebserver.in.service > $SYSTEMD_DIR/yajudge-grpcwebserver.service
echo "Created file $SYSTEMD_DIR/yajudge-grpcwebserver.service"


# Create systemd instance links

ln -f -s -T yajudge-master@.service $SYSTEMD_DIR/yajudge-master@$CONFIG_NAME.service
echo "$SYSTEMD_DIR/yajudge-master@.service symlinked to $SYSTEMD_DIR/yajudge-master@$CONFIG_NAME.service"

ln -f -s -T yajudge-grader@.service $SYSTEMD_DIR/yajudge-grader@$CONFIG_NAME.service
echo "$SYSTEMD_DIR/yajudge-grader@.service symlinked to $SYSTEMD_DIR/yajudge-grader@$CONFIG_NAME.service"


# Reload systemd configuration

systemctl daemon-reload
echo "Reloaded systemd configuration"


# Allow grpcwebserver to listen ports <1024
setcap 'cap_net_bind_service=+ep' "$BIN_DIR/yajudge-grpcwebserver"


# Make message on configuration

echo "Done. See README.md for next configuration stages"


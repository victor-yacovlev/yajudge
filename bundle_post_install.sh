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

dirs=("$LOG_DIR" "$PID_DIR" "$CACHE_DIR" "$COURSES_DIR" "$PROBLEMS_DIR" "$WORK_DIR" "$SYSTEM_DIR" "$CONF_DIR")
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

if [ -f $CONF_DIR/envoy-$CONFIG_NAME.yaml ]
then
    ENVOY_CONF=$CONF_DIR/envoy-$CONFIG_NAME.new.yaml
    echo "Found existing envoy configuration"
else
    ENVOY_CONF=$CONF_DIR/envoy-$CONFIG_NAME.yaml
fi

echo "Envoy configuration will be created in $ENVOY_CONF"

if [ -f /etc/nginx/sites-available/yajudge ]
then
    NGINX_CONF=/etc/nginx/sites-available/yajudge.new
    echo "Found existing nginx configuration"
else
    NGINX_CONF=/etc/nginx/sites-available/yajudge
fi

echo "Nginx configuration will be created in $NGINX_CONF"


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
sed -E "$repl" conf/envoy.in.yaml > $ENVOY_CONF
echo "Created file $ENVOY_CONF"
sed -E "$repl" conf/nginx.in.conf > $NGINX_CONF
echo "Created file $NGINX_CONF"


# Preprocess and create systemd files

cat systemd/yajudge-grader.slice > $SYSTEMD_DIR/yajudge-grader.slice
echo "Created file $SYSTEMD_DIR/yajudge-grader.slice"

sed -E "$repl" systemd/yajudge-grader-prepare.in.service > $SYSTEMD_DIR/yajudge-grader-prepare.service
echo "Created file $SYSTEMD_DIR/yajudge-grader-prepare.service"

sed -E "$repl" systemd/yajudge-grader@.in.service > $SYSTEMD_DIR/yajudge-grader@.service
echo "Created file $SYSTEMD_DIR/yajudge-grader@.service"

sed -E "$repl" systemd/yajudge-master@.in.service > $SYSTEMD_DIR/yajudge-master@.service
echo "Created file $SYSTEMD_DIR/yajudge-master@.service"

sed -E "$repl" systemd/yajudge-envoy@.in.service > $SYSTEMD_DIR/yajudge-envoy@.service
echo "Created file $SYSTEMD_DIR/yajudge-envoy@.service"


# Create systemd instance links

ln -f -s -T yajudge-master@.service $SYSTEMD_DIR/yajudge-master@$CONFIG_NAME.service
echo "$SYSTEMD_DIR/yajudge-master@.service symlinked to $SYSTEMD_DIR/yajudge-master@$CONFIG_NAME.service"

ln -f -s -T yajudge-envoy@.service $SYSTEMD_DIR/yajudge-envoy@$CONFIG_NAME.service
echo "$SYSTEMD_DIR/yajudge-envoy@.service symlinked to $SYSTEMD_DIR/yajudge-envoy@$CONFIG_NAME.service"

ln -f -s -T yajudge-grader@.service $SYSTEMD_DIR/yajudge-grader@$CONFIG_NAME.service
echo "$SYSTEMD_DIR/yajudge-grader@.service symlinked to $SYSTEMD_DIR/yajudge-grader@$CONFIG_NAME.service"


# Reload systemd configuration

systemctl daemon-reload
echo "Reloaded systemd configuration"


# Make message on configuration

echo "Done. See README.md for next configuration stages"


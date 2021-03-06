# Yajudge Servers

## Third-party prerequirements

This sofware requires these third-party components to run:

 1. PostgreSQL database server (provided by most Linux distributions)

 PostgreSQL in use by master server to store users, courses, submissions
 and other work time data.
 
 2. NGINX web server (provided by most Linux distributions)

 NGINX web server will serve web application static files and deal
 with SSL certificates.
 
 
## Installation

 1. Run install script 'post_install.sh' as root. This will create user
 and group named 'yajudge', set proper writable directories permissions
 and create configuration files:

   - /etc/yajudge/master-default.yaml
   - /etc/yajudge/envoy-default.yaml
   - /etc/yajudge/grader-default.yaml
   - /etc/yajudge/grpcwebserver.yaml
   - /etc/yajudge/sites-available/default.yaml
   - /etc/yajudge/sites-enabled/default.yaml
   - /etc/nginx/sites-available/yajudge-default.conf
   - /etc/systemd/system/yajudge-master@.service
   - /etc/systemd/system/yajudge-master@default.service
   - /etc/systemd/system/yajudge-grpcwebserver.service
   - /etc/systemd/system/yajudge-grader-prepare.service
   - /etc/systemd/system/yajudge-grader.slice
   - /etc/systemd/system/yajudge-grader@.service
   - /etc/systemd/system/yajudge-grader@default.service

 Note that it will not replace existing configuration files but will replace
 existing systemd files.

 To create several configurations running the same server set CONFIG_NAME
 environment variable before script run. Default value is `default` and this name
 in use by configuration file name suffices.

 2. Check created configuration files and create matching PostgreSQL database
 (default user name is 'yajudge', password 'yajudge' and database name 'yajudge')
 like this:

 ```
 > psql yajudge  # this might require root privileges or to be logged as postgres user 
 postgres=# create database yajudge;
 postgres=# create user yajudge with password 'yajudge';
 postgres=# grant all privileges on database yajudge to yajudge; 
 ```

 3. Initialize empty database structure by command
 `bin/yajudge-master initialize-database`

 4. Create Administrator user by command
 `bin/yajudge-master -C /etc/yajudge/master-default.yaml create-admin YOUR_ADMIN_LOGIN YOUR_ADMIN_PASSWORD`
 Note that `-C CONFIG_FILE_NAME` paremeter is required in case if you have several configurations.

 5. Unpack your courses and problems (not shipped within this package bundle)
 into directories specified by 'master-default.yaml' ('courses' and 'problems'
 subdirectories by default)

 7. Create course iteration entry by command
 `bin/yajudge-master -C /etc/yajudge/master-default.yaml start-course --title COURSE_TITLE --data COURSE_DATA_SUBDIR --url URL_PREFIX`

 8. Prepare system root to be in use within isolated runs. The most convient way is
 to use `debootstrap` command for most Linux distributions.
 

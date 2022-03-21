## Master Backend Server for Yajudge

### Prerequirements

 - Dart 2.12 or later
 - PostgreSQL 10 or later
 - protoc compiler

In order to use within Web interface target there are
additional third-party components required:

 - `nginx` web-server to serve static content exposed
by `yajudge_client` and handle SSL connections

 - [envoy proxy-server](https://www.envoyproxy.io) to
translate gRPC-web request from browsers into native
gRPC requests to master server.

Example configurations for nginx and envoy provided
in `conf` subdirectory.

### Build
Just type `make` from parent directory, or from this 
directory after package `yajudge_common` built.

### Configuration

#### Check your configuration file

Default instance configuration stored into file `/etc/yajudge/master-default.yaml`.

You can create more instances (for example in case of multiple subdomains running the same server) by
creating copies of `/etc/yajudge/master-default.yaml` file and corresponding 
`/etc/systemd/system/yajudge-master@default.service` symlink to systemd service instance.


#### Prepare database

Create PostgreSQL database and create user:

 ```
 > psql yajudge  # this might require root privileges or to be logged as postgres user 
 postgres=# create database yajudge;
 postgres=# create user yajudge with password 'database_password';
 postgres=# grant all privileges on database yajudge to yajudge;  
 ```

Then write into config file `/etc/yajudge/master-default.yaml` (or config file matching your instance)
corresponding database properties (hostname, user and password file location). 
Note that database password stored in separate file with access rights
accessible only to `yajudge` service user but not arbitrary users.  

#### Make initial database records

Master service will fail to start if there is database exists but not initialized.
To initialize database run the following command:

```
> yajudge-master initialize-database
```

**Warning:** this command will drop existing tables in database, be careful!

If you have several master service instances and want to initialize specific database, 
you also can pass instance config to command:

```
> yajudge-master -C /etc/yajudge/master-custom-instance.yaml initialize-database
```

Then create at least one administrator user able to login and create rest users:

```
> yajudge-master create-admin ADMIN_LOGIN_EMAIL ADMIN_PASSWORD
```

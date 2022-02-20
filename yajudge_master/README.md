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

#### Prepare database

Create PostgreSQL database and create user:

 ```
 > psql
 postgres=# create database yajudge;
 postgres=# create user yajudge with password 'database_password';
 postgres=# grant all privileges on database yajudge to yajudge;  
 ```

#### Make initial database records

There is no automatic database initialization yet :( So it will appear in some future. 

Import schema from [conf/postgresql_schema.sql](conf/postgresql_schema.sql):

```
> psql -d yajudge -U yajudge -W  < conf/postgresql_schema.sql
```

Then create Administrator user:
```
> psql -d yajudge -U yajudge -W
yajudge=> insert into users(first_name,last_name,email,password,default_role) values('John','Galt','admin@example.com','=qwerty',6);
```

Note on equal sign as first symbol in password - it has meaning as initial 'registration' password that keeps
unencrypted and must be changed later to some more secure, and 6 value of default role (administrator).


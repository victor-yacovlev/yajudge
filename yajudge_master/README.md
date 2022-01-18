# Yajudge Master Server

## Prerequirements
 - Dart 2.12 or later
 - PostgreSQL 10 or later
 - protoc compiler

## Build
Just type `make master` from parent directory.

## Configuration

### Prepare database

Create PostgreSQL database and create user:

 ```
 > psql
 postgres=# create database yajudge;
 postgres=# create user yajudge with password 'database_password';
 postgres=# grant all privileges on database yajudge to yajudge;  
 ```

### Make initial database records

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


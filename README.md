# kaminari_okoshi

### how to use

#### for not Rails

```
$ mkdir kaminari_okoshi && $_
$ git clone git@github.com:tko-t/kaminari_okoshi.git .
$ cp config/database.yml.sample config/database.yml
$ docker-compose build
$ docker-compose run --rm app ruby okosu <table_name> -d <your_database_name> [-options]
```

Enter your database connection information in config/database.yml

#### When to use Rails and containers

```
$ cd /any/rails_root/path
$ git clone git@github.com:tko-t/kaminari_okoshi.git ko
$ docker-compose exec <container_name> ruby ko/okosu <table_name> [-options]
```

... You may need to rebuild the container in some cases

#### for Rails in localhost 

```
$ cd /any/rails_root/path
$ git clone git@github.com:tko-t/kaminari_okoshi.git ko
$ ruby ko/okosu <table_name> [-options]
```

#### Options

options are eval'd. So specify it like a hash

* total  
number to create (default: 100000)
* step  
per commit (default: 1000)
* uniqs  
column name that should be unique (default: [])
* nulls  
column name that should be null (default: [])
* refs  
references maping (default: {})
* db  
connect to database (default: ['development', 'primary'])

#### Command Sample

```
$ ... "{ total: 100, step: 10, uniqs: ['email'], nulls: ['address'], refs: { country_id: { table: :countries, column: :id } }, db: ['development'] }"
```

refs can also be an Array

```
$ ... "{ total: 100, step: 10, refs: { country_id: [:countries, :id] }, db: ['development'] }"
```

#### Sample Values

* integer  
Integer within the number of digits limit
* float  
Float within the number of digits limit + '.0'
* string  
SecureRandom.hex within the number of digits limit
* boolean  
0 or 1
* date  
last 100 years
* datetime  
last 100 years
* text  
"text-" + SecureRandom.hex
* json  
'{}'

#### Custom Values

show [README or ext](https://github.com/tko-t/kaminari_okoshi/blob/master/ext/README.md)

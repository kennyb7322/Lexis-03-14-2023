#!/bin/sh

if [ $# -lt 6 ]; then
   echo "Expected 6 parameters...got "$0
   echo ; echo "Usage dmp_load_data.sh [<source host>] [<source port>] [<db>] [<dest host>] [<dest port>] [<dest user>]"
   echo
  exit
fi

src_host=${1}
src_port=${2}
database=${3}
dest_host=${4}
dest_port=${5}
dest_user=${6}
#dest_pass=${7}
src_user='dbadmin'

vault_key=$src_host"_"$src_port"_"$src_user
src_pass=`vault kv get -address=$VAULT_ADDRESS -namespace=$VAULT_NAMESPACE -field=pwd kv/$vault_key`

vault_key=$dest_host"_"$dest_port"_"$dest_user
dest_pass=`vault kv get -address=$VAULT_ADDRESS -namespace=$VAULT_NAMESPACE_AZURE -field=pwd kv/$vault_key`

echo `date`" Starting data dump for "${database}" from "${src_host}
mkdir -p output/${src_host}_${src_port}_to_${dest_host}

#echo "set autocommit = 1;set SESSION foreign_key_checks=0;" > output/${src_host}_${src_port}_to_${dest_host}/${database}.sql
echo "set SESSION foreign_key_checks=0;" > output/${src_host}_${src_port}_to_${dest_host}/${database}.sql

MYSQL_PWD=${src_pass} mysqldump -h ${src_host} -P${src_port} -u ${src_user} --master-data=2 --max_allowed_packet=512M --set-gtid-purged=OFF --no-create-info --skip-triggers --insert-ignore --quick --single-transaction --databases ${database}  >>  output/${src_host}_${src_port}_to_${dest_host}/${database}.sql
if ! [ "$?" == "0" ]; then
        echo "Dump failed. Please investigate "
        exit 1
fi

echo "commit;" >> output/${src_host}_${src_port}_to_${dest_host}/${database}.sql

#echo `date`" purging definers and myisam from dump file"
#sed -i 's/MyISAM/INNODB/;s/!50013 DEFINER=`[a-zA-Z0-9].*`@`%` SQL SECURITY DEFINER/ /;s/!50017 DEFINER=`root`@`localhost`/ /;s/ DEFINER=`[a-zA-Z0-9].*`@`%`/ /;s/DEFINER=`root`@`localhost`/ /g' output/${src_host}_${src_port}_to_${dest_host}/${src_host}.sql

echo `date`" Loading data to "${dest_host}
#MYSQL_PWD=${dest_pass} mysql -h${dest_host} -P${dest_port} -u${dest_user} -A --ssl-ca=/scratch/azure/DigiCertGlobalRootCA.crt.pem --ssl-capath=/scratch/azure ${database} -e"tee ${database}_ddl.log;source ${database}_data.sql;"
MYSQL_PWD=${dest_pass} mysql -h${dest_host} -P${dest_port} -u${dest_user} -C -A ${database} <  output/${src_host}_${src_port}_to_${dest_host}/${database}.sql >  output/${src_host}_${src_port}_to_${dest_host}/${database}.log 2>&1
if ! [ "$?" == "0" ]; then
        echo "Load of data failed. Please investigate "
        exit 0
fi

echo "Replication Info: `head -50 output/${src_host}_${src_port}_to_${dest_host}/${database}.sql | grep "CHANGE MASTER"`"

echo `date`" Data load finished review log..." output/${src_host}_${src_port}"_to_"${dest_host}/${database}".log for potential issues "

gzip -f output/${src_host}_${src_port}_to_${dest_host}/${database}.sql
if ! [ "$?" == "0" ]; then
       echo "gzip of data file failed. Please investigate "
       exit 1
fi


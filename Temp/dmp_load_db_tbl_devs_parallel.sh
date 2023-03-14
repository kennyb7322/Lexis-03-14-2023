#!/bin/sh

if [ $# -lt 7 ]; then
   echo "Expected 7 parameters...got "$0
   echo ; echo "Usage dmp_load_db_tbl_defs.sh [<source host>] [<source port>] [<db>] [<dest host>] [<dest port>] [<dest user>] [<dest pass>] [-f to force]"
   echo
  exit
fi

src_host=${1}
src_port=${2}
database=${3}
dest_host=${4}
dest_port=${5}
dest_user=${6}
dest_pass=${7}
force=${8}
src_user='dbadmin'
vault_key=$src_host"_"$src_port"_"$src_user
src_pass=`vault kv get -address=$VAULT_ADDRESS -namespace=$VAULT_NAMESPACE -field=pwd kv/$vault_key`

echo `date`" Starting dump DDL for "${database}" from "${src_host}":"${src_port}
mkdir -p output/${src_host}_${src_port}_to_${dest_host}

MYSQL_PWD=${src_pass} mysqldump -h ${src_host} -P${src_port} -u ${src_user} ${force} --set-gtid-purged=OFF --databases ${database} --add-drop-table --single-transaction --routines --no-data --skip-triggers >  output/${src_host}_${src_port}_to_${dest_host}/${database}_ddl.sql
if ! [ "$?" == "0" ]; then
        echo "Dump DB and table Definitions failed. Please investigate "
        exit 1
fi

echo `date`" running thru sed to remove definer and convert INNODB to innodb "
sed -i 's/INNODB/INNODB/;s/!50013 DEFINER=`[a-zA-Z0-9].*`@`%` SQL SECURITY DEFINER/!50013 SQL SECURITY INVOKER/;s/ / /;s/ DEFINER=`[a-zA-Z0-9].*`@`%` / /;s/ DEFINER="[a-zA-Z0-9].*"@"%" / /; s/utf8mb4_general_ci/utf8mb4_general_ci/g'  output/${src_host}_${src_port}_to_${dest_host}/${database}_ddl.sql
sed -i 's/tx_isolation/transaction_isolation/g' output/${src_host}_${src_port}_to_${dest_host}/${database}_ddl.sql
sed -i 's/ DEFINER=`[a-zA-Z0-9].*`@`[a-zA-Z0-9].*` / /g' output/${src_host}_${src_port}_to_${dest_host}/${database}_ddl.sql

if ! [ "$?" == "0" ]; then
        echo "sed for Dump DB and table Definitions failed. Please investigate "
        exit 1
fi


#build statements to change sql security on Functions and SPs
MYSQL_PWD=${src_pass} mysql -h ${src_host} -P${src_port} -u ${src_user} -sss -A information_schema -e"select CONCAT('ALTER ',ROUTINE_TYPE,' ',ROUTINE_SCHEMA,'.',ROUTINE_NAME,' SQL SECURITY INVOKER ;') from information_schema.routines where routine_schema = '${database}' and routine_type in ('FUNCTION','PROCEDURE') and security_type ='DEFINER';" >  output/${src_host}_${src_port}_to_${dest_host}/${database}_invoker_ddl.sql
if ! [ "$?" == "0" ]; then
        echo "Import DB and table Definitions failed. Please investigate "
        exit 1
fi

#
echo `date`" Loading DDL for "${database}" to "${dest_host}":"${dest_port}
MYSQL_PWD=${dest_pass} mysql -h${dest_host} -P${dest_port} -u${dest_user} -f -A -e"set SESSION foreign_key_checks=0;source  output/${src_host}_${src_port}_to_${dest_host}/${database}_ddl.sql;source output/${src_host}_${src_port}_to_${dest_host}/${database}_invoker_ddl.sql;" >  output/${src_host}_${src_port}_to_${dest_host}/${database}_ddl.log 2>&1
if ! [ "$?" == "0" ]; then
        echo "Load of DB and table Definitions failed. Please investigate "
        exit 1
fi
echo `date`" ddl load completed review " output/${src_host}_${src_port}_to_${dest_host}/${database}"_ddl.log for potential issues "

#echo `date`" loading timezone tables"
#MYSQL_PWD=${dest_pass} mysql -h${dest_host} -P${dest_port} -u${dest_user} -f -A -e"call mysql.az_load_timezones();"
#if ! [ "$?" == "0" ]; then
#  echo "Load of timezone tables failed. Please investigate "
#  exit 1
#fi
#echo `date`" timezone tables loaded"

gzip -f output/${src_host}_${src_port}_to_${dest_host}/${database}_ddl.sql
if ! [ "$?" == "0" ]; then
       echo "gzip of data file failed. Please investigate "
       exit 1
fi


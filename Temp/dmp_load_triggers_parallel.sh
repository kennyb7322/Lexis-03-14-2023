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

mkdir -p  output/${src_host}_${src_port}_to_${dest_host}
echo `date`" Starting dump of TRIGGERS for "${database}" from "${src_host}":"${src_port}

MYSQL_PWD=${src_pass} mysqldump -h ${src_host} -P${src_port} -u ${src_user} ${force} --set-gtid-purged=OFF --databases ${database} --single-transaction --no-data --triggers --add-drop-trigger --no-create-info >  output/${src_host}_${src_port}_to_${dest_host}/${database}_trg.sql
if ! [ "$?" == "0" ]; then
       echo "Dump of triggers failed. Please investigate "
       exit 1
fi

echo `date`" running triggers thru sed to remove definer  "
sed -i 's/MyISAM/INNODB/;s/!50013 DEFINER=`[a-zA-Z0-9].*`@`%` SQL SECURITY DEFINER/DEFINER REMOVED/;s/!50017 DEFINER=`root`@`localhost`/DEFINER REMOVED/;s/ DEFINER=`[a-zA-Z0-9].*`@`%`/ /g'  output/${src_host}_${src_port}_to_${dest_host}/${database}_trg.sql
if ! [ "$?" == "0" ]; then
        echo "sed for trigger failed. Please investigate "
        exit 1
fi

echo `date`" Loading TRIGGERS for "${database}" to "${dest_host}":"${dest_port}
#MYSQL_PWD=${dest_pass} mysql -h${dest_host} -P${dest_port} -u${dest_user} -A --ssl-ca=/scratch/azure/DigiCertGlobalRootCA.crt.pem --ssl-capath=/scratch/azure ${database} -e"tee ${database}_trg.log;source ${database}_trg.sql;"
MYSQL_PWD=${dest_pass} mysql -h${dest_host} -P${dest_port} -u${dest_user} -A ${database} -e"source  output/${src_host}_${src_port}_to_${dest_host}/${database}_trg.sql;" >  output/${src_host}_${src_port}_to_${dest_host}/${database}_trg.log 2>&1
if ! [ "$?" == "0" ]; then
        echo "Load of triggers failed. Please investigate "
        exit 1
fi

echo `date`" TRIGGER load completed review " output/${src_host}_${src_port}"_to_"${dest_host}/${database}"_trg.log for potential issues "

#gzip  output/${src_host}_${src_port}_to_${dest_host}/${database}_trg.sql
if ! [ "$?" == "0" ]; then
       echo "gzip of data file failed. Please investigate "
       exit 1
fi


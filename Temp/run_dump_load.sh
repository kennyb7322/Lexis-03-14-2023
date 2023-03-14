#!/bin/sh

if [ $# -gt 8 ] || [ $# -lt 7 ]; then
   echo "Expected 7 parameters ...got "$#"!"
   echo ; echo "Usage: "`basename $0`" [<source host>] [<source port>] [<dest host>] [<dest port>] [<dest user>] [<db|'ALL'>] [<INCLUDE-DATA|ONLY-DATA|NO-DATA>] [<dest password>]"
   echo
   exit
fi

src_host=${1}
src_port=${2}
dest_host=${3}
dest_port=${4}
dest_user=${5}
dest_pass=${8}
db=${6}
data=${7}
#force=${9}
src_user='dbadmin'
vault_key=$src_host"_"$src_port"_"$src_user
src_pass=`vault kv get -address=$VAULT_ADDRESS -namespace=$VAULT_NAMESPACE -field=pwd kv/$vault_key`

if [ "${8}" == "" ]
then
   vault_key=$dest_host"_"$dest_port"_"$dest_user
   dest_pass=`vault kv get -address=$VAULT_ADDRESS -namespace=$VAULT_NAMESPACE_AZURE -field=pwd kv/$vault_key`
else
  dest_pass=${8}
fi

if [ ${db}"XX" = "XX" ] || [ ${db} = "ALL" ]; then
   db='%'
fi

query="select schema_name from information_schema.SCHEMATA
     where schema_name not in ('.serversidedebugger','cacti','information_schema','mysql','percona','performance_schema','sys','sys_backup','tempdb','test','tmp')
       and schema_name like '${db}'
       order by schema_name;"

echo `date`" Starting dump and load process for "${src_host}":"${src_port}" to "${dest_host}":"${dest_port}

lines=`MYSQL_PWD=${src_pass} mysql -h ${src_host} -P${src_port} -u ${src_user} -ss --skip-column-names -A -e"${query}"`

if [ "$lines" == "" ]
then
        echo "There is no schema named ${db}, exiting..."
        exit 1
fi

for list_line in ${lines}
do
    echo `date`" Start processing for: "${list_line}
    if [ ${data} = "ONLY-DATA" ]; then
        sh dmp_load_data.sh ${src_host} ${src_port} ${list_line} ${dest_host} ${dest_port} ${dest_user} ${dest_pass}

        if ! [ "$?" == "0" ]; then
                echo "Dump and Load of table data failed. Please investigate "
                exit
        fi
    elif [ ${data} = "INCLUDE-DATA" ] || [ ${data} = "NO-DATA" ]; then
        sh dmp_load_db_tbl_defs.sh ${src_host} ${src_port} ${list_line} ${dest_host} ${dest_port} ${dest_user} ${dest_pass} ${force}
        if ! [ "$?" == "0" ]; then
                echo "Dump and Load of table DB and table Definitions failed. Please investigate "
                exit
        fi
        if [ ${data} = "INCLUDE-DATA" ]; then
                sh dmp_load_data.sh ${src_host} ${src_port} ${list_line} ${dest_host} ${dest_port} ${dest_user} ${dest_pass}
                if ! [ "$?" == "0" ]; then
                        echo "Dump and Load of table data failed. Please investigate "
                        exit
                fi
        fi

        sh dmp_load_triggers.sh ${src_host} ${src_port} ${list_line} ${dest_host} ${dest_port} ${dest_user} ${dest_pass} ${force}
        if ! [ "$?" == "0" ]; then
                echo "Dump and Load of table trigger failed. Please investigate "
                exit
        fi
    fi
    echo `date`" End processing for: "${list_line}
done


new_master=$1
PGHOME=/usr/pgsql-9.4
PGDATA=/var/lib/pgsql/9.4/data
trigger_command="$PGHOME/bin/pg_ctl promote -D $PGDATA"
# Prompte standby database.
/usr/bin/ssh -T postgres@$new_master $trigger_command -w
exit 0;
# .bash_profile

# Get the aliases and functions
if [ -f ~/.bashrc ]; then
	. ~/.bashrc
fi

# User specific environment and startup programs

PATH=$PATH:$HOME/.local/bin:$HOME/bin

export PATH

export PGHOME=/usr/txdb4.0
export PGDATA=/usr/txdbdata
export PATH=$PGHOME/bin:$PATH
export MANPATH=$PGHOME/share/man:$MANPATH
export LANG=zh_CN.utf8
export PGDATABASE=txdb_default
export DATE=`date +"%Y-%m-%d %H:%M:%S"`
export LD_LIBRARY_PATH=$PGHOME/lib:$LD_LIBRARY_PATH
alias tx_start='pg_ctl start -D $PGDATA -l $PGHOME/logfile'
alias tx_stop='pg_ctl stop -D $PGDATA -m fast -l $PGHOME/logfile'
alias tx_restart='pg_ctl -D $PGDATA -l $PGHOME/logfile restart'


PGPOOLHOME=/usr/tx_pgpool
export PGPOOLHOME
PATH=$PGPOOLHOME/bin:$PGHOME/bin:$PATH
export PATH

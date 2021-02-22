failed_node=$1
new_master=$2
trigger_file=$3
# Do nothing if standby goes down.
if [ $failed_node = 1 ]; then
        echo "stand by done"
        exit 0;
fi
# Create the trigger file.
/usr/bin/ssh -T $new_master /bin/touch $trigger_file
exit 0
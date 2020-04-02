#!/bin/bash
set -e

sed -i "s/SSH_PORT/$SSH_PORT/g" /etc/ssh/sshd_config
sed -i "s/8500/$PORT/g" /opt/coldfusion/cfusion/runtime/conf/server.xml
sed -i "s/8500/$PORT/g" /opt/startup/start-coldfusion.sh
service ssh start
sh /opt/startup/start-coldfusion.sh start



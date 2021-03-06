#!/bin/bash

set -e 

date
ps axjf

USER_NAME=$1
FQDN=$2
NPROC=$(nproc)
LOCAL_IP=`ifconfig|xargs|awk '{print $7}'|sed -e 's/[a-z]*:/''/'`
WITNESS_RPC_PORT=8090
WALLET_HTTP_RPC_PORT=8091
WALLET_RPC_PORT=8092
P2P_PORT=1776
PROJECT=testnet
GITHUB_REPOSITORY=https://github.com/BitSharesEurope/testnet.git
RELEASE=master
DCMAKE_BUILD_TYPE=Release
WITNESS_NODE=testnet_witness_node
CLI_WALLET=testnet_cli_wallet

echo "USER_NAME: $USER_NAME"
echo "FQDN: $FQDN"
echo "nproc: $NPROC"
echo "eth0: $LOCAL_IP"
echo "P2P_PORT: $P2P_PORT"
echo "WITNESS_RPC_PORT: $WITNESS_RPC_PORT"
echo "WALLET_HTTP_RPC_PORT: $WALLET_HTTP_RPC_PORT"
echo "WALLET_RPC_PORT: $WALLET_RPC_PORT"
echo "PROJECT: $PROJECT"
echo "GITHUB_REPOSITORY: $GITHUB_REPOSITORY"
echo "RELEASE: $RELEASE"
echo "DCMAKE_BUILD_TYPE: $DCMAKE_BUILD_TYPE"
echo "WITNESS_NODE: $WITNESS_NODE"
echo "CLI_WALLET: $CLI_WALLET"

echo "Begin Update..."
sudo apt-get -y update || exit 1;
# To avoid intermittent issues with package DB staying locked when next apt-get runs
sleep 5;

##################################################################################################
# Clone the python-graphenelib project from the Xeroc source repository. Install dependencies,   #
# then setup the libraries.                                                                      #
##################################################################################################
echo "Clone python-graphenelib project..."
cd /usr/local/src
time git clone https://github.com/xeroc/python-graphenelib.git
cd python-graphenelib
apt -y install libffi-dev libssl-dev python-dev python3-pip
pip3 install pip --upgrade
python3 setup.py install

##################################################################################################
# Install all necessary packages for building PRIVATE GRAPHENE witness node and CLI.             #
##################################################################################################
time apt -y install ntp g++ make cmake libbz2-dev libdb++-dev libdb-dev libssl-dev openssl \
                    libreadline-dev autoconf libtool libboost-all-dev

##################################################################################################
# Clone the TESTNET project from the BitShares Europe source repository. Initialize the project. #
# Eliminate the test folder to speed up the build time by about 20%.                             #
##################################################################################################
echo "Clone $PROJECT project..."
cd /usr/local/src
time git clone $GITHUB_REPOSITORY
cd $PROJECT
time git checkout $RELEASE
sed -i 's/add_subdirectory( tests )/#add_subdirectory( tests )/g' /usr/local/src/$PROJECT/CMakeLists.txt
sed -i 's/add_subdirectory(tests)/#add_subdirectory(tests)/g' /usr/local/src/$PROJECT/libraries/fc/CMakeLists.txt
sed -i 's%auto history_plug = node->register_plugin%//auto history_plug = node->register_plugin%g' /usr/local/src/$PROJECT/programs/witness_node/main.cpp
sed -i 's%auto market_history_plug = node->register_plugin%//auto market_history_plug = node->register_plugin%g' /usr/local/src/$PROJECT/programs/witness_node/main.cpp
sed -i 's%include_directories( vendor/equihash )%#include_directories( vendor/equihash )%g' /usr/local/src/$PROJECT/libraries/fc/CMakeLists.txt
sed -i 's%src/crypto/equihash.cpp%#src/crypto/equihash.cpp%g' /usr/local/src/$PROJECT/libraries/fc/CMakeLists.txt
sed -i 's%add_subdirectory( vendor/equihash )%#add_subdirectory( vendor/equihash )%g' /usr/local/src/$PROJECT/libraries/fc/CMakeLists.txt
sed -i 's%${CMAKE_CURRENT_SOURCE_DIR}/vendor/equihash%#${CMAKE_CURRENT_SOURCE_DIR}/vendor/equihash%g' /usr/local/src/$PROJECT/libraries/fc/CMakeLists.txt
sed -i 's%target_link_libraries( fc PUBLIC ${LINK_USR_LOCAL_LIB} equihash ${%target_link_libraries( fc PUBLIC ${LINK_USR_LOCAL_LIB} ${%g' /usr/local/src/$PROJECT/libraries/fc/CMakeLists.txt
sed -i 's/add_subdirectory( debug_node )/#add_subdirectory( debug_node )/g' /usr/local/src/$PROJECT/programs/CMakeLists.txt
sed -i 's/add_subdirectory( delayed_node )/#add_subdirectory( delayed_node )/g' /usr/local/src/$PROJECT/programs/CMakeLists.txt
sed -i 's/add_subdirectory( genesis_util )/#add_subdirectory( genesis_util )/g' /usr/local/src/$PROJECT/programs/CMakeLists.txt
sed -i 's/add_subdirectory( js_operation_serializer )/#add_subdirectory( js_operation_serializer )/g' /usr/local/src/$PROJECT/programs/CMakeLists.txt
sed -i 's/add_subdirectory( size_checker )/#add_subdirectory( size_checker )/g' /usr/local/src/$PROJECT/programs/CMakeLists.txt
sed -i 's/add_subdirectory( account_history )/#add_subdirectory( account_history )/g' /usr/local/src/$PROJECT/libraries/plugins/CMakeLists.txt
sed -i 's/add_subdirectory( market_history )/#add_subdirectory( market_history )/g' /usr/local/src/$PROJECT/libraries/plugins/CMakeLists.txt
sed -i 's/add_subdirectory( delayed_node )/#add_subdirectory( delayed_node )/g' /usr/local/src/$PROJECT/libraries/plugins/CMakeLists.txt
sed -i 's/add_subdirectory( debug_witness )/#add_subdirectory( debug_witness )/g' /usr/local/src/$PROJECT/libraries/plugins/CMakeLists.txt

##################################################################################################
# Build the PRIVATE GRAPHENE witness node and CLI wallet.                                        #
##################################################################################################
cd /usr/local/src/$PROJECT/
time git submodule update --init --recursive
time cmake -DCMAKE_BUILD_TYPE=$DCMAKE_BUILD_TYPE .
time make -j$NPROC

cp /usr/local/src/$PROJECT/programs/witness_node/witness_node /usr/bin/$WITNESS_NODE
cp /usr/local/src/$PROJECT/programs/cli_wallet/cli_wallet /usr/bin/$CLI_WALLET

##################################################################################################
# Configure graphene service. Enable it to start on boot.                                        #
##################################################################################################
cat >/lib/systemd/system/$PROJECT.service <<EOL
[Unit]
Description=Job that runs $PROJECT daemon
[Service]
Type=simple
Environment=statedir=/home/$USER_NAME/$PROJECT/witness_node
ExecStartPre=/bin/mkdir -p /home/$USER_NAME/$PROJECT/witness_node
ExecStart=/usr/bin/$WITNESS_NODE --data-dir /home/$USER_NAME/$PROJECT/witness_node
TimeoutSec=300
[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload
systemctl enable $PROJECT
##################################################################################################
# Start the graphene service to allow it to create the default configuration file. Stop the      #
# service, modify the config.ini file, then restart the service with the new settings applied.   #
##################################################################################################
service $PROJECT start
service $PROJECT stop
sed -i 's/# p2p-endpoint =/p2p-endpoint = '$LOCAL_IP':'$P2P_PORT'/g' /home/$USER_NAME/$PROJECT/witness_node/config.ini
sed -i 's/# rpc-endpoint =/rpc-endpoint = '$LOCAL_IP':'$RPC_PORT'/g' /home/$USER_NAME/$PROJECT/witness_node/config.ini
sed -i 's/level=debug/level=info/g' /home/$USER_NAME/$PROJECT/witness_node/config.ini
service $PROJECT start

##################################################################################################
# Create a script to launch the cli_wallet using a wallet file stored at                         #
# /home/$USER_NAME/$PROJECT/cli_wallet/wallet.json                                               #
##################################################################################################
mkdir /home/$USER_NAME/$PROJECT/cli_wallet/
cat >/home/$USER_NAME/launch-$PROJECT-wallet.sh <<EOL
/usr/bin/$CLI_WALLET -w /home/$USER_NAME/$PROJECT/cli_wallet/wallet.json \
                     -s ws://$LOCAL_IP:$WITNESS_RPC_PORT \
					 -H 127.0.0.1:$WALLET_HTTP_RPC_PORT \
					 -r 127.0.0.1:$WALLET_RPC_PORT
EOL
chmod +x /home/$USER_NAME/launch-$PROJECT-wallet.sh

##################################################################################################
# SSH to: <VMname>.<region>.cloudapp.azure.com                                                   #
# The fully qualified domain name (FQDN) can be found within the Azure Portal under "DNS name"   #
# Learn more: http://docs.bitshares.eu                                                           #
##################################################################################################

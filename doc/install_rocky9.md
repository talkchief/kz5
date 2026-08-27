This doc serves as a WIP for installing open source KAZOO and all its necessary components (CouchDB, RabbitMQ, FreeSWITCH, and Kamailio).

Packages are used where possible; building from source otherwise.

# Environment

## MUST SET HOST NAME PROPERLY

# System setup
sudo dnf install git
sudo dnf groupinstall “Development Tools”
sudo dnf install libcurses-devel wget

# Fetch KAZOO source

mkdir -p /opt/kazoo
git clone https://github.com/2600hz/kazoo5.git /opt/kazoo

# Prep Erlang Dependencies
curl -O https://raw.githubusercontent.com/kerl/kerl/master/kerl
chmod +x kerl
mv kerl /usr/bin
kerl update releases

# Build Erlang
kerl build 26.2 26.2
kerl install 26.2 /usr/local/otp-26.2

## activate for the duration of the shell session
. /usr/local/otp-26.2/activate

^ Add to .bashrc (or equivalent) to automatically have this version available.

# Build Kazoo
export FETCH_AS=https://github.com/
cd /opt/kazoo
make
make build-dev-release

# Grab Kazoo Configs
git clone https://github.com/2600hz/kazoo-configs-core/ /etc/kazoo

# Install RabbitMQ and CouchDB
sudo dnf install yum-utils -y
dnf install rabbitmq-server couchdb
rabbitmq-plugins enable rabbitmq_consistent_hash_exchange


# Set user/pass in CouchDB config.ini
# Copy that user/pass into /etc/kazoo/core/config.ini
# Change Kazoo port number to 5984/5986 for now

# Start RabbitMQ & CouchDB
systemctl start couchdb
systemctl start rabbitmq-server

# Start Kazoo!
cd /opt/kazoo/
make release

# kz_nodes:status(). in the erlang shell to test
#
# To start Kazoo Ecallmgr + Extensions
# kapps_controller:start_app(ecallmgr_extension).
# kapps_controller:start_app(ecallmgr).

# Install Kamailio
yum install kamailio-kazoo kamailio-outbound kamailio-uuid kamailio-tcpops kamailio-presence

# Grab Kamailio configs
git clone https://github.com/2600hz/kazoo-configs-kamailio

# Move files to right directories?

# Prepare Kamailio/Kazoo DB
kazoo-kamailio prepare
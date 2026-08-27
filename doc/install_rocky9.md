# Installing Open Source KAZOO (v5) on Rocky Linux 9

WIP: rough draft for installing open source KAZOO with its components
(CouchDB, RabbitMQ, FreeSWITCH, Kamailio). Packages are used where possible;
otherwise we build from source.

This assumes you have installed older KAZOO versions before and are comfortable
with Linux administration, so it mostly highlights what differs from the
classic install (OTP 26.2 via kerl, the dev release build, `/etc/kazoo`
configs, the kamailio-kazoo packages).

## 1. Environment

- **Set the host name properly.** KAZOO keys off the host name; make sure
  `/etc/hostname` and `/etc/hosts` are correct before starting anything.
- **FQDN must resolve.** KAZOO's node name becomes the distributed Erlang
  longname, so the FQDN must resolve both ways. Sanity check before building:
  `erl -name test` should come up as `test@<fqdn>`. If epmd reports `noport`
  or the shell crashes, fix DNS/`/etc/hosts` first.

## 2. System packages

Get the base toolchain and download helpers:

    sudo dnf install git
    sudo dnf groupinstall "Development Tools"
    sudo dnf install libcurses-devel wget

Optional but expected on a production box (fax/media): `sox`, `ghostscript`,
`imagemagick`, `libtiff-tools`, `libreoffice-writer` + a JRE, `zip unzip`,
`htmldoc`. Fax conversions need LibreOffice/Java; PDFs and media normalization
need the rest. (The sibling installation.md lists Debian names like
`libsox-fmt-all`; use the equivalent RPM packages here.)

## 3. Fetch KAZOO source

    sudo mkdir -p /opt/kazoo
    sudo git clone https://github.com/2600hz/kazoo5.git /opt/kazoo

## 4. Erlang (OTP 26.2)

KAZOO 5 builds on OTP 26.2, installed under `/usr/local/otp-26.2` via kerl.
Note: `doc/installation.md` still references Erlang 23 for Kazoo 5 — it is
stale; `make/erlang_version` (26.2) is authoritative.

Install and update kerl:

    curl -O https://raw.githubusercontent.com/kerl/kerl/master/kerl
    chmod +x kerl
    sudo mv kerl /usr/bin
    kerl update releases

Build and install OTP 26.2:

    kerl build 26.2 26.2
    kerl install 26.2 /usr/local/otp-26.2

Activate it for the duration of the shell session:

    . /usr/local/otp-26.2/activate

Add that `activate` line to `~/.bashrc` (or equivalent) so this OTP version is
available in every shell by default.

## 5. Build KAZOO (dev release)

`FETCH_AS` makes dep fetches resolve against `https://github.com/`. We build a
dev release here, not a packaged one:

    export FETCH_AS=https://github.com/
    cd /opt/kazoo
    make
    make build-dev-release

The dev release symlinks the beam files and reloads them on recompile, which is
handy for iterating but not what you'd deploy. For a production box use `make
build-release` instead (start with `make release REL=<node>`), or `make
build-tar-release` to create a single build for distribution.

## 5a. SUP tooling

Install the SUP tool and its bash completion:

    sudo ln -s /opt/kazoo/core/sup/priv/sup /usr/bin/sup
    sudo make sup_completion           # from repo root; creates sup.bash
    sudo cp sup.bash /etc/bash_completion.d/

If the path to KAZOO isn't right in the symlink, set `KAZOO_ROOT=/opt/kazoo`
(alias) instead.

## 6. KAZOO configs

KAZOO 5 keeps its runtime config in `/etc/kazoo` (matching the KAZOO 4 layout),
with per-node overrides in `/etc/kazoo/sys.config`:

    sudo git clone https://github.com/2600hz/kazoo-configs-core/ /etc/kazoo

## 7. CouchDB and RabbitMQ

Install both (enable EPEL first if you haven't already):

    sudo dnf install yum-utils -y
    sudo dnf install rabbitmq-server couchdb

Enable the consistent-hash-exchange plugin, which KAZOO's AMQP usage needs:

    sudo rabbitmq-plugins enable rabbitmq_consistent_hash_exchange

Configure CouchDB:
- set the admin user/pass in CouchDB's `config.ini`
- mirror that user/pass into `/etc/kazoo/core/config.ini`
- point KAZOO at CouchDB's HTTP/HTTPS ports (5984/5986) for now

Start both services:

    sudo systemctl start couchdb
    sudo systemctl start rabbitmq-server

## 8. Start KAZOO and verify

    cd /opt/kazoo/
    make release

In the Erlang shell, confirm the node sees the rest of the cluster:

    kz_nodes:status().

Then bring up the media layer and its extensions:

    kapps_controller:start_app(ecallmgr_extension).
    kapps_controller:start_app(ecallmgr).

With CouchDB, RabbitMQ, and KAZOO all running, `epmd -names` should list all
three node names registered; a missing name means a service didn't finish
starting.

## 9. Kamailio

Install the KAZOO-bundled Kamailio packages:

    sudo dnf install kamailio-kazoo kamailio-outbound kamailio-uuid kamailio-tcpops kamailio-presence

Grab the Kamailio configs (TODO: figure out where these live; move files into
the right directories):

    git clone https://github.com/2600hz/kazoo-configs-kamailio

Initialize the Kamailio/KAZOO database:

    kazoo-kamailio prepare

## Open items / TODO

- Proper hostname setup steps
- CouchDB: exact user/pass, node naming, and why 5984/5986 is used "for now"
- Enable services at boot and firewall rules
- Placement of the Kamailio configs
- FreeSWITCH is listed as a component but not yet covered

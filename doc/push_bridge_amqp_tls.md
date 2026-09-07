# Bridge remote-broker TLS

Bridge configuration now supports verified TLS independently of provider HTTPS.
Set these string values in the protected service JSON:

```json
{
  "PUSH_BRIDGE_AMQP_HOST": "broker.example.invalid",
  "PUSH_BRIDGE_AMQP_TLS": "true",
  "PUSH_BRIDGE_AMQP_PORT": "5671",
  "PUSH_BRIDGE_AMQP_CA_FILE": "/etc/kazoo-push-bridge/broker-ca.pem"
}
```

These are additions to the full configuration example, not a complete working
configuration. Omit the CA field to use system trust. With TLS true and no
explicit port, the port defaults5671. Explicit ports are preserved. Port5671
alone does not enable TLS. Absent/false TLS retains existing plaintext AMQP;
use verified TLS for remote brokers, not an untrusted plaintext network.

The optional CA file must be directly inside `/etc/kazoo-push-bridge`, protected
like the other validated service files. The launcher parses the bounded PEM
bytes before installer changes, rejects private keys/malformed PEM and includes
the CA in its exact permission-preparation list. Never commit populated JSON,
broker passwords or provider credentials. The production source server and its
broker binding are not changed by this feature.

The runtime uses a Python default client TLS context, certificate verification,
hostname verification and minimum TLS1.2. It passes the explicit context and
configured broker hostname to the pinned AMQPStorm2.11.1 connection. No insecure
verification/SNI override or plaintext retry fallback is offered. Errors loading
CA material are sanitized. A trusted certificate for the wrong host must fail.

Use the ordinary modular installer and verification:

```sh
sudo bash scripts/install-kazoo5.sh push-bridge
sudo bash scripts/install-kazoo5.sh --verify-only push-bridge
```

The installer already fingerprints, copies and validates the modified launcher,
validator and runtime. No separate manual TLS deployment path is needed.

## Verification scope

`0d2bfe/session53173/b60ebe` passed112 bridge tests and installer dispatch in an
isolated network namespace. Five new TLS tests use actual pinned AMQPStorm
parameter/socket-wrapper code plus real in-memory TLS handshakes with temporary
synthetic certificates. Trusted matching host succeeds; wrong host/untrusted CA
fail. Other additions verify strict settings/default ports, protected CA parsing
and permissions. No production broker/provider/device was contacted.

This is not a real remote AMQPS broker acceptance or mobile-delivery result.
Development deployment retains its isolated local plaintext acceptance broker.
Cross-server broker authentication, reconnect/timeout/failure handling, durable
retry/expiry and test-device ringing remain explicit release gates.

Main-SH development deployment `1ff54f/session31649/02ae6d` passed; independent
`--verify-only push-bridge` and the TLS suite using the new installed venv passed
`9f2d32/session48034/f1ad28`. Current content-addressed release is
`24e085e77183a418ded9df942a6dd16dc5883eacb2e7ca30d85a3cc7e4ab6c76`,
enabled/active registered consumer PID323748, zero automatic restarts. Previous
releases are retained. No production setting, provider notification or local
broker TLS/listener/binding was changed.

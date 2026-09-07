# Push bridge dependency lock

Source inspection:2026-09-07. Target: CPython3.11, RockyLinux9 x86_64.
`services/push-bridge/requirements.lock` records exact versions and SHA-256
wheel digests from primary PyPI JSON metadata. Installation uses the explicit
PyPI HTTPS index and `--only-binary=:all: --require-hashes`. No source-build
fallback or unpinned transitive dependencies are permitted.

AMQPStorm2.11.1/pamqp2.3.0 retain the imported consumer's major-version API;
AMQPStorm3/pamqp4 need separate client/broker acceptance. Other versions were
returned by direct PyPI metadata reads during preparation. These pins are not
a security audit, successful install or runtime compatibility certification.

Primary metadata:

- [AMQPStorm2.11.1](https://pypi.org/pypi/AMQPStorm/2.11.1/json), [pamqp2.3.0](https://pypi.org/pypi/pamqp/2.3.0/json)
- [google-auth2.57.1](https://pypi.org/pypi/google-auth/2.57.1/json), [pyasn1-modules0.4.2](https://pypi.org/pypi/pyasn1-modules/0.4.2/json), [pyasn1 0.6.4](https://pypi.org/pypi/pyasn1/0.6.4/json)
- [cryptography50.0.1](https://pypi.org/pypi/cryptography/50.0.1/json), [cffi2.1.1](https://pypi.org/pypi/cffi/2.1.1/json), [pycparser3.0](https://pypi.org/pypi/pycparser/3.0/json)
- [requests2.34.2](https://pypi.org/pypi/requests/2.34.2/json), [charset-normalizer3.5.1](https://pypi.org/pypi/charset-normalizer/3.5.1/json), [idna3.19](https://pypi.org/pypi/idna/3.19/json), [urllib3 2.7.0](https://pypi.org/pypi/urllib3/2.7.0/json), [certifi2026.7.22](https://pypi.org/pypi/certifi/2026.7.22/json)
- [h2 4.4.1](https://pypi.org/pypi/h2/4.4.1/json), [hyperframe6.1.0](https://pypi.org/pypi/hyperframe/6.1.0/json), [hpack4.2.0](https://pypi.org/pypi/hpack/4.2.0/json)
- [ecdsa0.19.2](https://pypi.org/pypi/ecdsa/0.19.2/json), [six1.17.0](https://pypi.org/pypi/six/1.17.0/json)

Cryptography permits four reviewed CPython3.9/3.11 ABI3 x86_64 wheels for
manylinux2.28/2.34. CFFI uses CPython3.11 manylinux2.17 x86_64.
Charset-normalizer permits its universal or CPython3.11 Linux x86_64 wheel;
other dependencies use universal wheels. Pip hash-checks the selected artifact.
No wheels were downloaded/executed by the editing agent. Root must run isolated
dependency installation, `pip check`, the launcher version verifier and actual
SDK integration tests. The lock is deliberately independent of provider keys.

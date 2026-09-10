"""Synthetic broker fixture only. Credentials arrive over private stdin."""
import json
import re
import sys
import amqpstorm

connection = None
try:
    config = json.loads(sys.stdin.readline())
    assert config['host'] == '10.1.0.44'
    assert re.fullmatch(r'kz5-maintenance-probe-[a-f0-9]{16}', config['vhost'])
    connection = amqpstorm.Connection(config['host'], config['user'], config['password'],
                                     virtual_host=config['vhost'], heartbeat=60, timeout=10)
    channel = connection.channel()
    channel.confirm_deliveries()
    channel.queue.declare(queue='owned-probe', durable=False, auto_delete=False)
    message = None
    print('READY', flush=True)
    for line in sys.stdin:
        command = line.strip()
        if command == 'publish':
            channel.basic.publish('synthetic-maintenance-probe', routing_key='owned-probe')
        elif command == 'get':
            message = channel.basic.get(queue='owned-probe', no_ack=False)
            assert message is not None and message.body == 'synthetic-maintenance-probe'
        elif command == 'ack':
            assert message is not None
            message.ack()
            message = None
        elif command == 'close':
            connection.close()
            connection = None
            print('OK', flush=True)
            break
        else:
            raise ValueError('Unexpected command')
        print('OK', flush=True)
except Exception:
    print('REFUSED', flush=True)
    sys.exit(1)
finally:
    if connection is not None:
        connection.close()

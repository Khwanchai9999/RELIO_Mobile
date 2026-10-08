import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';

void main() {
  test('bonded entries deduplicate by normalized Bluetooth address', () {
    final devices = deduplicateBondedBluetoothDevices([
      const BondedBluetoothDevice(
        address: 'f8:5e:0b:ba:96:36',
        name: 'Realme 10 Pro 5G',
        bondState: 'BONDED',
      ),
      const BondedBluetoothDevice(
        address: 'F8:5E:0B:BA:96:36',
        name: 'Duplicate label must not alter identity',
        bondState: 'BONDED',
      ),
      const BondedBluetoothDevice(
        address: '4C:DD:31:E2:95:5F',
        name: 'Galaxy S9+',
        bondState: 'BONDING',
      ),
    ]);

    expect(devices, hasLength(1));
    expect(devices.single.address, 'F8:5E:0B:BA:96:36');
    expect(devices.single.endpointId, 'classic:F8:5E:0B:BA:96:36');
    expect(devices.single.bondState, 'BONDED');
  });

  test('same display name does not merge different paired identities', () {
    final devices = deduplicateBondedBluetoothDevices([
      const BondedBluetoothDevice(
        address: 'F8:5E:0B:BA:96:36',
        name: 'RELIO',
        bondState: 'BONDED',
      ),
      const BondedBluetoothDevice(
        address: '4C:DD:31:E2:95:5F',
        name: 'RELIO',
        bondState: 'BONDED',
      ),
    ]);

    expect(devices, hasLength(2));
    expect(
      devices.map((device) => device.endpointId),
      containsAll(['classic:F8:5E:0B:BA:96:36', 'classic:4C:DD:31:E2:95:5F']),
    );
  });
}

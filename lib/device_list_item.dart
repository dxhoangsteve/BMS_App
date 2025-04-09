import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class DeviceListItem extends StatelessWidget {
  final BluetoothDevice device;
  final int rssi;
  final String deviceType;
  final AdvertisementData advertisementData;
  final VoidCallback onTap;

  const DeviceListItem({
    Key? key,
    required this.device,
    required this.rssi,
    required this.deviceType,
    required this.advertisementData,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Tạo tên hiển thị tốt hơn
    String displayName = device.name.isNotEmpty
        ? device.name
        : advertisementData.localName.isNotEmpty
            ? advertisementData.localName
            : 'Thiết bị không xác định';

    // Lấy phần ngắn của ID để hiển thị dễ đọc hơn
    String shortId = device.id.id.replaceAll(':', '').substring(0, 8);

    // Chọn icon phù hợp
    IconData deviceIcon =
        deviceType == 'BLE' ? Icons.bluetooth : Icons.bluetooth_audio;

    // Xác định màu dựa trên cường độ tín hiệu
    Color signalColor;
    if (rssi > -70) {
      signalColor = Colors.green;
    } else if (rssi > -90) {
      signalColor = Colors.orange;
    } else {
      signalColor = Colors.red;
    }

    return Card(
      elevation: 2,
      margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ListTile(
        title: Text(
          displayName,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ID: ${device.id.id}'),
            Row(
              children: [
                Text('Cường độ tín hiệu: '),
                Text(
                  '$rssi dBm',
                  style: TextStyle(
                      color: signalColor, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            Text('Loại: $deviceType'),
          ],
        ),
        leading: CircleAvatar(
          backgroundColor: Colors.blue.shade100,
          child: Icon(
            deviceIcon,
            color: Colors.blue,
          ),
        ),
        trailing: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
          child: Text('Kết nối'),
        ),
        onTap: onTap,
      ),
    );
  }
}

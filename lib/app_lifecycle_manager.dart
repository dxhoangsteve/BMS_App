import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class AppLifecycleManager extends StatefulWidget {
  final Widget child;

  const AppLifecycleManager({Key? key, required this.child}) : super(key: key);

  @override
  _AppLifecycleManagerState createState() => _AppLifecycleManagerState();
}

class _AppLifecycleManagerState extends State<AppLifecycleManager>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached ||
        state == AppLifecycleState.paused) {
      _disconnectAllDevices();
    }
  }

  Future<void> _disconnectAllDevices() async {
    print('Ngắt kết nối tất cả thiết bị BLE khi thoát ứng dụng');
    try {
      // Lấy danh sách tất cả thiết bị đã kết nối
      List<BluetoothDevice> connectedDevices =
          await FlutterBluePlus.connectedDevices;

      // Ngắt kết nối từng thiết bị
      for (BluetoothDevice device in connectedDevices) {
        try {
          await device.disconnect();
          print('Đã ngắt kết nối thiết bị ${device.id}');
        } catch (e) {
          print('Lỗi khi ngắt kết nối thiết bị ${device.id}: $e');
        }
      }
    } catch (e) {
      print('Lỗi khi ngắt kết nối tất cả thiết bị: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

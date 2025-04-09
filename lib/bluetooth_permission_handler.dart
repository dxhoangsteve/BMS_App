import 'package:permission_handler/permission_handler.dart';

class BluetoothPermissionHandler {
  Future<bool> requestPermissions() async {
    // Yêu cầu nhiều quyền cùng lúc
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      // Quyền vị trí có thể cần thiết trên các phiên bản Android cũ hơn
      Permission.location,
    ].request();

    // Kiểm tra xem tất cả các quyền cần thiết đã được cấp chưa
    bool allGranted = true;
    statuses.forEach((permission, status) {
      if (status != PermissionStatus.granted) {
        allGranted = false;
      }
    });

    return allGranted;
  }

  Future<bool> checkPermissions() async {
    // Kiểm tra xem quyền đã được cấp chưa
    bool bluetoothGranted = await Permission.bluetooth.isGranted;
    bool bluetoothScanGranted = await Permission.bluetoothScan.isGranted;
    bool bluetoothConnectGranted = await Permission.bluetoothConnect.isGranted;
    bool locationGranted = await Permission.location.isGranted;

    return bluetoothGranted &&
        bluetoothScanGranted &&
        bluetoothConnectGranted &&
        locationGranted;
  }
}

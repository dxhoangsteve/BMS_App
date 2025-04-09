import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BluetoothManager {
  static final BluetoothManager _instance = BluetoothManager._internal();
  factory BluetoothManager() => _instance;
  BluetoothManager._internal();

  // FlutterBluePlus không còn sử dụng .instance nữa
  final FlutterBluePlus flutterBlue = FlutterBluePlus();

  // Streams - API thay đổi cách truy cập
  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;
  Stream<bool> get isScanning => FlutterBluePlus.isScanning;
  Stream<BluetoothAdapterState> get adapterState =>
      FlutterBluePlus.adapterState;

  // Bắt đầu quét các thiết bị Bluetooth
  Future<void> startScan(
      {Duration timeout = const Duration(seconds: 10)}) async {
    try {
      // Kiểm tra xem Bluetooth có được bật không
      if (await isBluetoothEnabled()) {
        // Bắt đầu quét - API đã thay đổi
        await FlutterBluePlus.startScan(timeout: timeout);
      } else {
        print('Bluetooth chưa được bật');
      }
    } catch (e) {
      print('Lỗi khi bắt đầu quét: $e');
      rethrow;
    }
  }

  // Dừng quét thiết bị Bluetooth
  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      print('Lỗi khi dừng quét: $e');
      rethrow;
    }
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      // Dừng quét trước khi kết nối
      await FlutterBluePlus.stopScan();

      // Chờ một chút
      await Future.delayed(Duration(milliseconds: 300));

      // Kết nối với thiết bị
      await device.connect(
        autoConnect: false,
        timeout: Duration(seconds: 8),
      );

      print('Kết nối thành công với thiết bị ${device.id.id}');

      // QUAN TRỌNG: KHÔNG gọi requestMtu
    } catch (e) {
      print('Lỗi khi kết nối thiết bị: $e');
      try {
        device.disconnect();
      } catch (_) {}
      rethrow;
    }
  }

  // Ngắt kết nối từ thiết bị Bluetooth
  Future<void> disconnectFromDevice(BluetoothDevice device) async {
    try {
      await device.disconnect();
    } catch (e) {
      print('Lỗi khi ngắt kết nối thiết bị: $e');
      rethrow;
    }
  }

  // Thêm phương thức này vào class BluetoothManager
  Future<void> disconnectAllDevices() async {
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

  // Kiểm tra xem Bluetooth có được bật không
  Future<bool> isBluetoothEnabled() async {
    try {
      BluetoothAdapterState state = await FlutterBluePlus.adapterState.first;
      return state == BluetoothAdapterState.on;
    } catch (e) {
      print('Lỗi khi kiểm tra trạng thái Bluetooth: $e');
      return false;
    }
  }

  // Xác định loại thiết bị (BLE hoặc Standard) chính xác hơn
  String getDeviceType(ScanResult result) {
    // Cách chính xác nhất để xác định thiết bị BLE
    if (result.advertisementData.manufacturerData.isNotEmpty ||
        result.advertisementData.serviceUuids.isNotEmpty ||
        result.advertisementData.serviceData.isNotEmpty) {
      return 'BLE';
    }

    // Nếu thiết bị có thể kết nối, có khả năng cao là thiết bị BLE
    if (result.advertisementData.connectable) {
      return 'BLE';
    }

    // Mac address thường bắt đầu với một số prefix nhất định cho BLE
    String macPrefix =
        result.device.id.id.split(':').take(3).join(':').toUpperCase();
    if (['00:1A:7D', '00:1E:C0', '00:25:F1'].contains(macPrefix)) {
      return 'BLE';
    }

    // Mặc định là Standard Bluetooth
    return 'Standard Bluetooth';
  }

  // Thêm phương thức này vào cuối class BluetoothManager
  Future<bool> connectWithRetry(BluetoothDevice device,
      {int maxRetries = 2}) async {
    int attempts = 0;
    while (attempts < maxRetries) {
      try {
        attempts++;
        print('Đang thử kết nối lần $attempts...');

        await connectToDevice(device);
        return true;
      } catch (e) {
        print('Lần thử $attempts thất bại: $e');

        if (attempts >= maxRetries) {
          return false;
        }

        // Chờ trước khi thử lại
        await Future.delayed(Duration(seconds: 1));
      }
    }
    return false;
  }
}

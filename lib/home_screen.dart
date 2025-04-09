import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'bluetooth_manager.dart';
import 'device_list_item.dart';
import 'bluetooth_permission_handler.dart';
import 'device_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final BluetoothManager _bluetoothManager = BluetoothManager();
  final BluetoothPermissionHandler _permissionHandler =
      BluetoothPermissionHandler();

  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;
  StreamSubscription<bool>? _isScanningSubscription;

  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  bool _permissionsGranted = false;
  bool _isBluetoothOn = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _setupBluetoothListeners();
  }

  Future<void> _checkPermissions() async {
    bool granted = await _permissionHandler.requestPermissions();
    setState(() {
      _permissionsGranted = granted;
    });
    if (granted) {
      _checkBluetoothStatus();
    }
  }

  Future<void> _checkBluetoothStatus() async {
    bool isOn = await _bluetoothManager.isBluetoothEnabled();
    setState(() {
      _isBluetoothOn = isOn;
    });
    if (isOn) {
      _startScan();
    } else {
      _showBluetoothOffDialog();
    }
  }

  void _setupBluetoothListeners() {
    // Lắng nghe các thay đổi trạng thái Bluetooth adapter
    _adapterStateSubscription = _bluetoothManager.adapterState.listen((state) {
      bool isOn = state == BluetoothAdapterState.on;
      setState(() {
        _isBluetoothOn = isOn;
      });

      if (isOn) {
        _startScan();
      } else {
        _bluetoothManager.stopScan();
        _showBluetoothOffDialog();
      }
    });

    // Lắng nghe kết quả quét
    _scanResultsSubscription = _bluetoothManager.scanResults.listen((results) {
      setState(() {
        _scanResults = results;
      });
    }, onError: (error) {
      print('Lỗi khi nhận kết quả quét: $error');
    });

    // Lắng nghe trạng thái quét
    _isScanningSubscription = _bluetoothManager.isScanning.listen((isScanning) {
      setState(() {
        _isScanning = isScanning;
      });
    }, onError: (error) {
      print('Lỗi khi nhận trạng thái quét: $error');
    });
  }

  Future<void> _startScan() async {
    if (_permissionsGranted && _isBluetoothOn && !_isScanning) {
      try {
        await _bluetoothManager.startScan();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi bắt đầu quét: $e')),
        );
      }
    }
  }

  void _showBluetoothOffDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Bluetooth đang tắt'),
          content: Text('Vui lòng bật Bluetooth để quét các thiết bị.'),
          actions: <Widget>[
            TextButton(
              child: Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    // Hiển thị dialog đang kết nối
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Đang kết nối'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Đang kết nối tới thiết bị...'),
            ],
          ),
        );
      },
    );

    try {
      // Sử dụng phương thức kết nối với retry
      bool success = await _bluetoothManager.connectWithRetry(device);

      // Đóng dialog
      Navigator.of(context).pop();

      if (success) {
        // Thêm đoạn này để tránh timeout khi khám phá dịch vụ
        await Future.delayed(Duration(milliseconds: 500));

        // Chuyển đến màn hình chi tiết sau khi kết nối thành công
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => DeviceDetailScreen(device: device),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể kết nối với thiết bị')),
        );
      }
    } catch (e) {
      // Đóng dialog nếu đang hiển thị
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi: $e')),
      );
    }
  }

  void _showConnectionFailDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Không thể kết nối'),
          content: Text(
              'Đã xảy ra lỗi khi kết nối với thiết bị BLE. Vui lòng thử lại sau.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Đóng'),
            ),
          ],
        );
      },
    );
  }

// Thêm phương thức này để hiển thị lỗi kết nối
  void _showConnectionErrorDialog(BluetoothDevice device) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Lỗi kết nối'),
          content: Text(
            'Không thể kết nối tới thiết bị. Vui lòng kiểm tra xem thiết bị có sẵn sàng để kết nối không và thử lại.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Đóng'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _connectToDevice(device);
              },
              child: Text('Thử lại'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _adapterStateSubscription?.cancel();
    _scanResultsSubscription?.cancel();
    _isScanningSubscription?.cancel();
    _bluetoothManager.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Quét Bluetooth'),
        actions: [
          if (_isScanning)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
        ],
      ),
      body: !_permissionsGranted
          ? _buildPermissionsRequest()
          : !_isBluetoothOn
              ? _buildBluetoothOffMessage()
              : _buildDeviceList(),
      floatingActionButton: FloatingActionButton(
        onPressed:
            _isScanning ? () => _bluetoothManager.stopScan() : _startScan,
        child: Icon(_isScanning ? Icons.stop : Icons.search),
        tooltip: _isScanning ? 'Dừng quét' : 'Bắt đầu quét',
      ),
    );
  }

  Widget _buildPermissionsRequest() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Cần quyền truy cập Bluetooth.'),
          SizedBox(height: 16),
          ElevatedButton(
            onPressed: _checkPermissions,
            child: Text('Cấp quyền'),
          ),
        ],
      ),
    );
  }

  Widget _buildBluetoothOffMessage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bluetooth_disabled, size: 80, color: Colors.grey),
          SizedBox(height: 16),
          Text('Bluetooth đang tắt'),
          SizedBox(height: 16),
          Text('Vui lòng bật Bluetooth để quét các thiết bị'),
          SizedBox(height: 24),
          ElevatedButton(
            onPressed: _checkBluetoothStatus,
            child: Text('Kiểm tra lại'),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    if (_scanResults.isEmpty) {
      return Center(
        child: _isScanning
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Đang quét thiết bị...'),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Không tìm thấy thiết bị nào'),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _startScan,
                    child: Text('Quét lại'),
                  ),
                ],
              ),
      );
    }

    return ListView.builder(
      itemCount: _scanResults.length,
      itemBuilder: (context, index) {
        final result = _scanResults[index];
        return DeviceListItem(
          device: result.device,
          rssi: result.rssi,
          deviceType: _bluetoothManager.getDeviceType(result),
          advertisementData: result.advertisementData,
          onTap: () => _connectToDevice(result.device),
        );
      },
    );
  }
}

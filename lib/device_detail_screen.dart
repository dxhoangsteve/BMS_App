import 'package:bms1/bms_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'bluetooth_manager.dart';

class DeviceDetailScreen extends StatefulWidget {
  final BluetoothDevice device;

  const DeviceDetailScreen({Key? key, required this.device}) : super(key: key);

  @override
  _DeviceDetailScreenState createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  final BluetoothManager _bluetoothManager = BluetoothManager();
  List<BluetoothService> _services = [];
  bool _isLoading = true;
  bool _isConnected = true;

  @override
  void initState() {
    super.initState();
    _checkConnectionAndDiscoverServices();
  }

  Future<void> _checkConnectionAndDiscoverServices() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Kiểm tra kết nối
      List<BluetoothDevice> connectedDevices =
          await FlutterBluePlus.connectedDevices;
      _isConnected = connectedDevices.any((d) => d.id == widget.device.id);

      if (!_isConnected) {
        // Thử kết nối lại nếu mất kết nối
        await _bluetoothManager.connectWithRetry(widget.device);
        _isConnected = true;
      }

      // Khám phá dịch vụ
      _services = await widget.device.discoverServices();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('Lỗi: $e');
      setState(() {
        _isLoading = false;
        _isConnected = false;
      });
    }
  }

  Future<void> _scanForDevices() async {
    try {
      await FlutterBluePlus.startScan(timeout: Duration(seconds: 4));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đang quét thiết bị...')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi khi quét: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    String deviceName = widget.device.name.isNotEmpty
        ? widget.device.name
        : 'Thiết bị ${widget.device.id.id.substring(0, 8)}';

    return Scaffold(
      appBar: AppBar(
        title: Text(_isConnected ? 'Kết nối: $deviceName' : 'Mất kết nối'),
        actions: [
          IconButton(
            icon: Icon(Icons.battery_full),
            onPressed: _openBmsScreen,
            tooltip: 'Phân tích BMS',
          ),
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _checkConnectionAndDiscoverServices,
            tooltip: 'Làm mới',
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : !_isConnected
              ? _buildReconnectView()
              : _buildServiceList(),
      floatingActionButton: FloatingActionButton(
        onPressed: _scanForDevices,
        child: Icon(Icons.search),
        tooltip: 'Quét thiết bị',
      ),
    );
  }

  void _openBmsScreen() {
    if (_services.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => BmsDetailScreen(
            device: widget.device,
            services: _services,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Vui lòng đợi khám phá dịch vụ hoàn tất')),
      );
    }
  }

  Widget _buildReconnectView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bluetooth_disabled, size: 80, color: Colors.grey),
          SizedBox(height: 16),
          Text('Mất kết nối với thiết bị'),
          SizedBox(height: 16),
          ElevatedButton(
            onPressed: _checkConnectionAndDiscoverServices,
            child: Text('Kết nối lại'),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceList() {
    if (_services.isEmpty) {
      return Center(child: Text('Không tìm thấy dịch vụ nào'));
    }

    return ListView.builder(
      itemCount: _services.length,
      itemBuilder: (context, index) {
        BluetoothService service = _services[index];
        return ExpansionTile(
          title: Text(
            'Dịch vụ: ${service.uuid.toString()}',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          children: service.characteristics
              .map((c) => _buildCharacteristicTile(c))
              .toList(),
        );
      },
    );
  }

  Widget _buildCharacteristicTile(BluetoothCharacteristic characteristic) {
    // Lấy UUID dưới dạng chuỗi
    String uuidString = characteristic.uuid.toString();

    // Cắt chuỗi an toàn
    String shortUuid =
        uuidString.length > 8 ? uuidString.substring(0, 8) + '...' : uuidString;

    return ListTile(
      title: Text('Đặc tính: $shortUuid'),
      subtitle: Text('Thuộc tính: ${_getPropertiesString(characteristic)}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (characteristic.properties.read)
            IconButton(
              icon: Icon(Icons.visibility),
              onPressed: () => _readCharacteristic(characteristic),
            ),
          if (characteristic.properties.write)
            IconButton(
              icon: Icon(Icons.edit),
              onPressed: () => _writeToCharacteristic(characteristic),
            ),
          if (characteristic.properties.notify ||
              characteristic.properties.indicate)
            IconButton(
              icon: Icon(Icons.notifications),
              onPressed: () => _subscribeToCharacteristic(characteristic),
            ),
        ],
      ),
    );
  }

  String _getPropertiesString(BluetoothCharacteristic characteristic) {
    List<String> props = [];
    if (characteristic.properties.read) props.add('Đọc');
    if (characteristic.properties.write) props.add('Ghi');
    if (characteristic.properties.notify) props.add('Thông báo');
    if (characteristic.properties.indicate) props.add('Chỉ báo');
    return props.join(', ');
  }

  Future<void> _readCharacteristic(
      BluetoothCharacteristic characteristic) async {
    try {
      List<int> value = await characteristic.read();
      String hexString =
          value.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Giá trị: $hexString')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi khi đọc: $e')),
      );
    }
  }

  Future<void> _writeToCharacteristic(
      BluetoothCharacteristic characteristic) async {
    // Đơn giản hóa, ở đây bạn có thể thêm dialog để nhập giá trị
    try {
      await characteristic.write([0x01, 0x02, 0x03]);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã ghi thành công')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi khi ghi: $e')),
      );
    }
  }

  Future<void> _subscribeToCharacteristic(
      BluetoothCharacteristic characteristic) async {
    try {
      await characteristic.setNotifyValue(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã đăng ký nhận thông báo')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi khi đăng ký: $e')),
      );
    }
  }
}

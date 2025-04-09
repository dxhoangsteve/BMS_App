import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'bms_analyzer.dart';
import 'cell_detail_screen.dart';

class BmsDetailScreen extends StatefulWidget {
  final BluetoothDevice device;
  final List<BluetoothService> services;

  const BmsDetailScreen({
    Key? key,
    required this.device,
    required this.services,
  }) : super(key: key);

  @override
  _BmsDetailScreenState createState() => _BmsDetailScreenState();
}

class _BmsDetailScreenState extends State<BmsDetailScreen>
    with WidgetsBindingObserver {
  late BmsType _bmsType;
  BluetoothCharacteristic? _writeCharacteristic;
  BluetoothCharacteristic? _notifyCharacteristic;
  List<int> _receivedData = [];
  List<int> _lastRequestData = [];
  String _lastRequestType = "";
  String _lastUpdateTime = 'Chưa có dữ liệu';
  String _lastError = '';
  Map<String, dynamic> _parsedData = {};
  Timer? _requestTimer;
  StreamSubscription? _notifySubscription;
  bool _isProcessingData = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bmsType = BmsAnalyzer.detectBmsType(widget.device, widget.services);
    _setupBms();
  }

  @override
  void dispose() {
    _requestTimer?.cancel();
    _notifySubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      print("App resumed, reinitializing BMS connection");
      _setupBms();
    }
  }

  void _setupBms() async {
    print("Bắt đầu thiết lập BMS...");
    try {
      BluetoothService? targetService;
      for (var service in widget.services) {
        String uuid = service.uuid.toString().toUpperCase();
        if (uuid.contains('FFE0')) {
          targetService = service;
          print("Đã tìm thấy service FFE0: ${service.uuid}");
          break;
        }
      }

      if (targetService == null) {
        _lastError = "Không tìm thấy service phù hợp";
        setState(() {});
        return;
      }

      for (var char in targetService.characteristics) {
        String uuid = char.uuid.toString().toUpperCase();
        if (uuid.contains('FFE1')) {
          _notifyCharacteristic = char;
          print("Đã tìm thấy notify characteristic FFE1");
        }
        if (uuid.contains('FFE2') &&
            (char.properties.write || char.properties.writeWithoutResponse)) {
          _writeCharacteristic = char;
          print("Đã chọn write characteristic FFE2");
        }
      }

      // Nếu không tìm thấy FFE2, dùng FFE1 làm dự phòng
      if (_writeCharacteristic == null && _notifyCharacteristic != null) {
        if (_notifyCharacteristic!.properties.write ||
            _notifyCharacteristic!.properties.writeWithoutResponse) {
          _writeCharacteristic = _notifyCharacteristic;
          print("Dùng FFE1 làm write characteristic dự phòng");
        }
      }

      if (_notifyCharacteristic == null) {
        _lastError = "Không tìm thấy notify characteristic";
        setState(() {});
        return;
      }
      if (_writeCharacteristic == null) {
        _lastError = "Không tìm thấy write characteristic";
        setState(() {});
        return;
      }

      await _notifyCharacteristic!.setNotifyValue(true);
      _notifySubscription?.cancel();
      _notifySubscription = _notifyCharacteristic!.value.listen((data) {
        if (data.isNotEmpty) {
          print("Nhận được ${data.length} bytes: ${_bytesToHexString(data)}");
          _onDataReceived(data);
        }
      });

      setState(() {});
      if (_writeCharacteristic != null) {
        _sendBmsRequest();
      }

      _requestTimer?.cancel();
      _requestTimer = Timer.periodic(Duration(seconds: 5), (timer) {
        if (_writeCharacteristic != null) {
          _sendBmsRequest();
        }
      });
    } catch (e) {
      print("Lỗi khi thiết lập BMS: $e");
      _lastError = "Lỗi thiết lập: $e";
      setState(() {});
    }
  }

  Future<void> _sendBmsRequest() async {
    if (_writeCharacteristic == null) return;

    List<int> command;
    String requestType;

    if (_bmsType == BmsType.JK) {
      if (_lastRequestType == "JK BMS Cell Info") {
        command = BmsAnalyzer.createJkBmsDeviceInfoRequest();
        requestType = "JK BMS Device Info";
      } else {
        command = BmsAnalyzer.createJkBmsCellInfoRequest();
        requestType = "JK BMS Cell Info";
      }
    } else {
      if (_lastRequestType == "ANT BMS Status") {
        command = BmsAnalyzer.createAntBmsDeviceInfoRequest();
        requestType = "ANT BMS Device Info";
      } else {
        command = BmsAnalyzer.createAntBmsStatusRequest();
        requestType = "ANT BMS Status";
      }
    }

    setState(() {
      _lastRequestData = command;
      _lastRequestType = requestType;
    });

    try {
      if (_writeCharacteristic!.properties.writeWithoutResponse) {
        await _writeCharacteristic!.write(command, withoutResponse: true);
      } else if (_writeCharacteristic!.properties.write) {
        await _writeCharacteristic!.write(command);
      }
    } catch (e) {
      _lastError = "Lỗi gửi yêu cầu: $e";
      setState(() {});
    }
  }

  void _onDataReceived(List<int> data) {
    setState(() {
      _lastUpdateTime = DateTime.now().toString();
      _receivedData.addAll(data);
    });

    if (_isBmsData(data)) {
      _parseBmsData();
    }
  }

  bool _isBmsData(List<int> data) {
    if (data.length < 4) return false;
    if (_bmsType == BmsType.JK) {
      if (data.length >= 5 &&
          data[0] == 0x55 &&
          data[1] == 0xAA &&
          data[2] == 0xEB &&
          data[3] == 0x90 &&
          (data[4] == 0x01 || data[4] == 0x02 || data[4] == 0x03)) {
        return true;
      }
    } else {
      if (data[0] == 0xAA &&
          data[1] == 0x55 &&
          data[2] == 0x90 &&
          data[3] == 0xEB) {
        return true;
      }
    }
    return false;
  }

  void _parseBmsData() {
    if (_isProcessingData || _receivedData.isEmpty) return;
    _isProcessingData = true;

    try {
      int index = 0;
      const int frameLength =
          300; // Độ dài khung dữ liệu JK BMS, điều chỉnh nếu cần
      while (index < _receivedData.length) {
        List<int> dataToParse = _receivedData.sublist(index);
        Map<String, dynamic> result = _bmsType == BmsType.JK
            ? BmsAnalyzer.parseJkBmsData(dataToParse)
            : BmsAnalyzer.parseAntBmsData(dataToParse);

        if (result.isNotEmpty) {
          setState(() {
            _parsedData = result;
          });
          index += frameLength;
        } else {
          break;
        }
      }
      if (index > 0) {
        _receivedData = _receivedData.sublist(index);
      }
    } catch (e) {
      print("Lỗi khi phân tích dữ liệu: $e");
    } finally {
      _isProcessingData = false;
    }
  }

  String _bytesToHexString(List<int> bytes) {
    return bytes
        .map((e) => e.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
  }

  void _clearData() {
    setState(() {
      _receivedData = [];
      _parsedData = {};
    });
  }

  Future<void> _sendControlCommand(int register, int value) async {
    if (_writeCharacteristic == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Không thể gửi lệnh: Characteristic không sẵn sàng')),
      );
      return;
    }

    // Tạo lệnh write_register theo định dạng JK BMS
    List<int> command = [
      0xAA, 0x55, 0x90, 0xEB, // Header
      0x02, // Command (write_register)
      register, // Register: 0x01 (sạc), 0x02 (xả), 0x03 (cân bằng)
      value, 0x00, 0x00, 0x00, // Value: 0x01 (bật), 0x00 (tắt)
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // Padding
    ];
    int crc = BmsAnalyzer.calculateCrc(command, 19);
    command.add(crc);

    print("Gửi lệnh điều khiển: ${_bytesToHexString(command)}");
    try {
      // Ghi lệnh với phản hồi để đảm bảo BMS nhận được
      await _writeCharacteristic!.write(command, withoutResponse: false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Đã gửi lệnh thành công: ${register == 0x01 ? "Sạc" : register == 0x02 ? "Xả" : "Cân bằng"} ${value == 0x01 ? "Bật" : "Tắt"}')),
      );
      // Chờ một chút rồi gửi yêu cầu cập nhật trạng thái
      await Future.delayed(Duration(milliseconds: 1000));
      _sendBmsRequest();
    } catch (e) {
      print("Lỗi khi gửi lệnh: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi khi gửi lệnh: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_bmsType == BmsType.JK ? 'JK BMS' : 'ANT BMS'),
        actions: [
          IconButton(
            icon: Icon(Icons.delete),
            onPressed: _clearData,
            tooltip: 'Xóa dữ liệu',
          ),
        ],
        backgroundColor: Colors.blueAccent,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDeviceInfo(),
            SizedBox(height: 16),
            _buildRequestInfo(),
            SizedBox(height: 16),
            _buildResponseInfo(),
            SizedBox(height: 16),
            _buildParsedDataCard(),
            SizedBox(height: 16),
            _buildControlButtons(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _sendBmsRequest,
        child: Icon(Icons.refresh),
        tooltip: 'Gửi yêu cầu thủ công',
        backgroundColor: Colors.blueAccent,
      ),
    );
  }

  Widget _buildDeviceInfo() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Thông tin thiết bị',
                style: Theme.of(context).textTheme.titleLarge),
            SizedBox(height: 8),
            Text(
                'Tên: ${widget.device.name.isNotEmpty ? widget.device.name : "Không xác định"}'),
            Text('ID: ${widget.device.id.id}'),
            Text('Loại BMS: ${_bmsType == BmsType.JK ? "JK BMS" : "ANT BMS"}'),
            Text('Số lượng dịch vụ: ${widget.services.length}'),
            if (_lastError.isNotEmpty)
              Container(
                margin: EdgeInsets.only(top: 8),
                padding: EdgeInsets.all(8),
                color: Colors.red.shade50,
                child: Text('Lỗi: $_lastError',
                    style: TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestInfo() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Yêu cầu đã gửi',
                style: Theme.of(context).textTheme.titleLarge),
            SizedBox(height: 8),
            Text('Loại yêu cầu: $_lastRequestType'),
            SizedBox(height: 8),
            if (_lastRequestData.isNotEmpty) ...[
              Text('Dữ liệu yêu cầu (HEX):'),
              Container(
                padding: EdgeInsets.all(8),
                color: Colors.grey[200],
                width: double.infinity,
                child: SelectableText(_bytesToHexString(_lastRequestData),
                    style: TextStyle(fontFamily: 'monospace')),
              ),
            ] else
              Text('Chưa gửi yêu cầu nào',
                  style: TextStyle(fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }

  Widget _buildResponseInfo() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Phản hồi nhận được',
                style: Theme.of(context).textTheme.titleLarge),
            SizedBox(height: 8),
            Text('Độ dài dữ liệu: ${_receivedData.length} bytes'),
            Text('Cập nhật lúc: $_lastUpdateTime'),
            SizedBox(height: 8),
            if (_receivedData.isNotEmpty) ...[
              Text('Dữ liệu thô (HEX):'),
              Container(
                padding: EdgeInsets.all(8),
                color: Colors.grey[200],
                width: double.infinity,
                child: SelectableText(
                  _bytesToHexString(_receivedData.length > 100
                      ? _receivedData.sublist(0, 100) + [0x2E, 0x2E, 0x2E]
                      : _receivedData),
                  style: TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ] else
              Text('Chưa nhận được dữ liệu',
                  style: TextStyle(fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }

  Widget _buildParsedDataCard() {
    if (_parsedData.isEmpty) {
      return Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: Text('Chưa có dữ liệu phân tích')),
        ),
      );
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Dữ liệu đã phân tích',
                    style: Theme.of(context).textTheme.titleLarge),
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            CellDetailScreen(parsedData: _parsedData),
                      ),
                    );
                  },
                  child: Text('Xem chi tiết cell'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent),
                ),
              ],
            ),
            SizedBox(height: 16),
            if (_parsedData.containsKey('voltage'))
              _buildDataRow('Điện áp tổng',
                  '${_parsedData['voltage'].toStringAsFixed(3)} V'),
            if (_parsedData.containsKey('current'))
              _buildDataRow('Dòng điện',
                  '${_parsedData['current'].toStringAsFixed(3)} A'),
            if (_parsedData.containsKey('power'))
              _buildDataRow(
                  'Công suất', '${_parsedData['power'].toStringAsFixed(3)} W'),
            if (_parsedData.containsKey('soc'))
              _buildDataRow('SOC', '${_parsedData['soc']}%'),
            if (_parsedData.containsKey('soh'))
              _buildDataRow('SOH', '${_parsedData['soh']}%'),
            if (_parsedData.containsKey('cellCount'))
              _buildDataRow('Số lượng cell', '${_parsedData['cellCount']}'),
            if (_parsedData.containsKey('temperature1')) ...[
              SizedBox(height: 12),
              Text('Nhiệt độ:', style: Theme.of(context).textTheme.titleMedium),
              SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Chip(
                    label: Text(
                        'Cảm biến 1: ${_parsedData['temperature1'].toStringAsFixed(1)} °C',
                        style: TextStyle(fontSize: 12))),
                Chip(
                    label: Text(
                        'Cảm biến 2: ${_parsedData['temperature2'].toStringAsFixed(1)} °C',
                        style: TextStyle(fontSize: 12))),
                if (_parsedData.containsKey('temperature3'))
                  Chip(
                      label: Text(
                          'Cảm biến 3: ${_parsedData['temperature3'].toStringAsFixed(1)} °C',
                          style: TextStyle(fontSize: 12))),
                if (_parsedData.containsKey('temperature4'))
                  Chip(
                      label: Text(
                          'Cảm biến 4: ${_parsedData['temperature4'].toStringAsFixed(1)} °C',
                          style: TextStyle(fontSize: 12))),
                if (_parsedData.containsKey('temperature5'))
                  Chip(
                      label: Text(
                          'Cảm biến 5: ${_parsedData['temperature5'].toStringAsFixed(1)} °C',
                          style: TextStyle(fontSize: 12))),
                if (_parsedData.containsKey('mosfetTemp'))
                  Chip(
                      label: Text(
                          'MOSFET: ${_parsedData['mosfetTemp'].toStringAsFixed(1)} °C',
                          style: TextStyle(fontSize: 12))),
              ]),
            ],
            if (_parsedData.containsKey('charging') &&
                _parsedData.containsKey('discharging')) ...[
              SizedBox(height: 12),
              Text('Trạng thái:',
                  style: Theme.of(context).textTheme.titleMedium),
              SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Chip(
                    label: Text(
                        'Sạc: ${_parsedData['charging'] ? "Bật" : "Tắt"}',
                        style: TextStyle(fontSize: 12))),
                Chip(
                    label: Text(
                        'Xả: ${_parsedData['discharging'] ? "Bật" : "Tắt"}',
                        style: TextStyle(fontSize: 12))),
                if (_parsedData.containsKey('balancing'))
                  Chip(
                      label: Text(
                          'Cân bằng: ${_parsedData['balancing'] ? "Bật" : "Tắt"}',
                          style: TextStyle(fontSize: 12))),
              ]),
            ],
            if (_parsedData.containsKey('remainCapacity'))
              _buildDataRow('Dung lượng còn lại',
                  '${_parsedData['remainCapacity'].toStringAsFixed(3)} Ah'),
            if (_parsedData.containsKey('totalCapacity'))
              _buildDataRow('Dung lượng định mức',
                  '${_parsedData['totalCapacity'].toStringAsFixed(3)} Ah'),
            if (_parsedData.containsKey('cycles'))
              _buildDataRow('Số chu kỳ sạc', '${_parsedData['cycles']}'),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButtons() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Điều khiển BMS',
                style: Theme.of(context).textTheme.titleLarge),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    ElevatedButton(
                      onPressed: () => _sendControlCommand(0x01, 0x01),
                      child: Text('Bật sạc'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green),
                    ),
                    SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () => _sendControlCommand(0x01, 0x00),
                      child: Text('Tắt sạc'),
                      style:
                          ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    ),
                  ],
                ),
                Column(
                  children: [
                    ElevatedButton(
                      onPressed: () => _sendControlCommand(0x02, 0x01),
                      child: Text('Bật xả'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green),
                    ),
                    SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () => _sendControlCommand(0x02, 0x00),
                      child: Text('Tắt xả'),
                      style:
                          ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    ),
                  ],
                ),
                Column(
                  children: [
                    ElevatedButton(
                      onPressed: () => _sendControlCommand(0x03, 0x01),
                      child: Text('Bật cân bằng'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green),
                    ),
                    SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () => _sendControlCommand(0x03, 0x00),
                      child: Text('Tắt cân bằng'),
                      style:
                          ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
              flex: 2,
              child:
                  Text(label, style: TextStyle(fontWeight: FontWeight.w500))),
          Expanded(flex: 3, child: Text(value)),
        ],
      ),
    );
  }
}

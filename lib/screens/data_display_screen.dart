import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/bms_data.dart';

class DataDisplayScreen extends StatefulWidget {
  final Stream<String> dataStream;

  const DataDisplayScreen({Key? key, required this.dataStream}) : super(key: key);

  @override
  State<DataDisplayScreen> createState() => _DataDisplayScreenState();
}

class _DataDisplayScreenState extends State<DataDisplayScreen> {
  BmsData? _latestData;
  int _packetCount = 0;

  @override
  void initState() {
    super.initState();
    _subscribeToData();
  }

  void _subscribeToData() {
    widget.dataStream.listen((dataString) {
      try {
        final jsonData = jsonDecode(dataString);
        setState(() {
          _latestData = BmsData.fromJson(jsonData);
          _packetCount++;
        });
      } catch (e) {
        print('Error parsing data: $e');
      }
    });
  }

  Widget _buildBatteryStatus() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDataRow('SOC:', '${_latestData==null?0:_latestData?.soc ?? '--'} %'),
            if (_latestData != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: _latestData!.soc / 100, 
                  minHeight: 20,
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _getSocColor(_latestData==null?0:_latestData!.soc),
                  ),
                ),
              ),
            ],
            _buildDataRow('Điện áp:', '${_latestData==null?0:_latestData?.voltage ?? '--'} V'),
            _buildDataRow('Dòng điện:', '${_latestData==null?0:_latestData?.current ?? '--'} A'),
            
            const SizedBox(height: 8),
            _buildDataRow('SOH:', '${_latestData?.soh ?? '--'} %'),
            _buildDataRow('Dung lượng còn lại:', '${_latestData?.capacity ?? '--'} Ah'),
            _buildDataRow('Số vòng sạc:', '${_latestData?.cycles ?? '--'}',
                valueColor: Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _buildCellVoltagesAndTemperature() {
    // Tính toán các giá trị nhiệt độ
    double avgTemp = 0.0;
    double maxTemp = 0.0;
    double minTemp = 0.0;
    double diffTemp = 0.0;
    
    // Kiểm tra xem có dữ liệu nhiệt độ không và mảng có phần tử không
    if (_latestData != null && _latestData!.temperatures.isNotEmpty && _latestData!.temperatures.length >= 4) {
      List<int> temps = _latestData!.temperatures;
      int sum = temps.reduce((a, b) => a + b);
      avgTemp = sum / temps.length;
      maxTemp = temps.reduce((a, b) => a > b ? a : b).toDouble();
      minTemp = temps.reduce((a, b) => a < b ? a : b).toDouble();
      diffTemp = maxTemp - minTemp;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cell Voltages card
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Điện áp',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  _buildDataRow('Trung bình:', '${_latestData?.averageVoltage.toStringAsFixed(3) ?? '0.000'} V'),
                  _buildDataRow('Lớn nhất:', '${_latestData?.maxVoltage.toStringAsFixed(3) ?? '0.000'} V'),
                  _buildDataRow('Nhỏ nhất:', '${_latestData?.minVoltage.toStringAsFixed(3) ?? '0.000'} V'),
                  _buildDataRow('Chênh lệch:', '${_latestData?.voltageDifference.toStringAsFixed(3) ?? '0.000'} V'),
                ],
              ),
            ),
          ),
        ),
        
        // Temperature card
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Nhiệt độ',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  _buildDataRow('T1:', '${_getTemperature(0)} °C'),
                  _buildDataRow('T2:', '${_getTemperature(1)} °C'),
                  _buildDataRow('T3:', '${_getTemperature(2)} °C'),
                  _buildDataRow('T4:', '${_getTemperature(3)} °C'),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Phương thức an toàn để lấy giá trị nhiệt độ
  int _getTemperature(int index) {
    if (_latestData == null || 
        _latestData!.temperatures.isEmpty || 
        index >= _latestData!.temperatures.length) {
      return 0;
    }
    return _latestData!.temperatures[index];
  }

  Widget _buildCellVoltagesGrid() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Chi tiêt các cell',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            if (_latestData != null) ...[
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 4,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _latestData!.cellVoltages.length,
                itemBuilder: (context, index) {
                  final voltage = _latestData!.cellVoltages[index];
                  final isMax = voltage == _latestData!.maxVoltage;
                  final isMin = voltage == _latestData!.minVoltage;
                  return Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isMax
                          ? Colors.green.withOpacity(0.2)
                          : isMin
                              ? Colors.red.withOpacity(0.2)
                              : Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'C${index + 1}: ${voltage.toStringAsFixed(3)} V',
                      textAlign: TextAlign.center,
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }


  Widget _buildMosfetStatus() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('MOSFETs Status',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildMosfetRow('Mở sạc FET:', _latestData?.chargeFet ?? false),
            _buildMosfetRow(
                'Mở xả FET:', _latestData?.dischargeFet ?? false),
            _buildMosfetRow('Điện chờ FET:', _latestData?.controlFet ?? false),
          ],
        ),
      ),
    );
  }

  Widget _buildDataRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value,
              style:
                  TextStyle(fontWeight: FontWeight.w500, color: valueColor)),
        ],
      ),
    );
  }

  Widget _buildMosfetRow(String label, bool isOn) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isOn ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              isOn ? 'ON' : 'OFF',
              style: TextStyle(
                color: isOn ? Colors.green[700] : Colors.red[700],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getSocColor(int soc) {
    if (soc < 20) return Colors.red;
    if (soc < 50) return Colors.orange;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vinfast BMS Monitor'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8.0),
              children: [
                _buildBatteryStatus(),
                _buildCellVoltagesAndTemperature(),
                _buildCellVoltagesGrid(),
               // _buildTemperatureGrid(),
                _buildMosfetStatus(),
              ],
            ),
          ),
          Container(
            color: Colors.grey[800],
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _latestData != null ? Colors.green : Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _latestData != null ? 'Connected' : 'Disconnected',
                      style: const TextStyle(color: Colors.white),
                    ),
                     const SizedBox(width: 8),
                    Text('        Brolab.vn',
                      style: const TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
                Text(
                  'Packets: $_packetCount',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
          
        ],
      ),
    );
  }
} 
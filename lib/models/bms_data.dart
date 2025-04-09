class BmsData {
  // Battery Status
  final double voltage;
  final double current;
  final int soc;
  final int soh;
  final double capacity;
  final int cycles;

  // Cell Voltages
  final double averageVoltage;
  final double maxVoltage;
  final double minVoltage;
  final double voltageDifference;
  final List<double> cellVoltages;

  // Temperature
  final List<int> temperatures;

  // MOSFETs Status
  final bool chargeFet;
  final bool dischargeFet;
  final bool controlFet;

  // Static instance để lưu trữ giá trị mới nhất
  static BmsData _latestData = BmsData(
    voltage: 0.0,
    current: 0.0,
    soc: 0,
    soh: 0,
    capacity: 0.0,
    cycles: 0,
    averageVoltage: 0.0,
    maxVoltage: 0.0,
    minVoltage: 0.0,
    voltageDifference: 0.0,
    cellVoltages: List.filled(22, 0.0),
    temperatures: List.filled(4, 0),
    chargeFet: false,
    dischargeFet: false,
    controlFet: false,
  );

  // Getter để lấy dữ liệu mới nhất
  static BmsData get latestData => _latestData;

  BmsData({
    required this.voltage,
    required this.current,
    required this.soc,
    required this.soh,
    required this.capacity,
    required this.cycles,
    required this.averageVoltage,
    required this.maxVoltage,
    required this.minVoltage,
    required this.voltageDifference,
    required this.cellVoltages,
    required this.temperatures,
    required this.chargeFet,
    required this.dischargeFet,
    required this.controlFet,
  });

  // Tạo bản sao của đối tượng hiện tại với các giá trị mới
  BmsData copyWith({
    double? voltage,
    double? current,
    int? soc,
    int? soh,
    double? capacity,
    int? cycles,
    double? averageVoltage,
    double? maxVoltage,
    double? minVoltage,
    double? voltageDifference,
    List<double>? cellVoltages,
    List<int>? temperatures,
    bool? chargeFet,
    bool? dischargeFet,
    bool? controlFet,
  }) {
    return BmsData(
      voltage: voltage ?? this.voltage,
      current: current ?? this.current,
      soc: soc ?? this.soc,
      soh: soh ?? this.soh,
      capacity: capacity ?? this.capacity,
      cycles: cycles ?? this.cycles,
      averageVoltage: averageVoltage ?? this.averageVoltage,
      maxVoltage: maxVoltage ?? this.maxVoltage,
      minVoltage: minVoltage ?? this.minVoltage,
      voltageDifference: voltageDifference ?? this.voltageDifference,
      cellVoltages: cellVoltages ?? this.cellVoltages,
      temperatures: temperatures ?? this.temperatures,
      chargeFet: chargeFet ?? this.chargeFet,
      dischargeFet: dischargeFet ?? this.dischargeFet,
      controlFet: controlFet ?? this.controlFet,
    );
  }

  factory BmsData.fromJson(Map<String, dynamic> json) {
    try {
      // Lấy id và data từ JSON
      final String id = json['id'] ?? '0x0';
      final List<dynamic> rawData = json['data'] ?? [];
      
      // Chuyển đổi dữ liệu hex string thành danh sách int
      final List<int> data = rawData.map((hex) {
        if (hex is String) {
          String hexStr = hex.startsWith('0x') ? hex.substring(2) : hex;
          return int.parse(hexStr, radix: 16);
        } else if (hex is int) {
          return hex;
        }
        return 0;
      }).toList();

      // Tạo một bản sao từ dữ liệu mới nhất hiện có
      BmsData updatedData = _latestData;

      // Xử lý dữ liệu dựa trên ID
      switch (id) {
        case '0x309':
          if (data.length >= 8) {
            // Voltage: byte 2 và 3, nhân với 0.002
            final voltageRaw = (data[2] << 8) | data[3];
            double newVoltage = voltageRaw * 0.002;

            // Current: byte 6 và 7, nhân với 0.02, xử lý số có dấu
            int currentRaw = (data[6] << 8) | data[7];
            if (currentRaw > 0x7FFF) {
              currentRaw -= 0x10000;
            }
            double newCurrent = currentRaw * 0.02;

            updatedData = updatedData.copyWith(
              voltage: newVoltage,
              current: newCurrent,
              chargeFet: (data[0] == 0x01 || data[0] == 0x11),
              dischargeFet: (data[0] == 0x10 || data[0] == 0x11),
              controlFet: ((data[1] & 0x03) == 0x01 || (data[1] & 0x03) == 0x03),
            );
          }
          break;

        case '0x30A':
          if (data.length >= 8) {
            updatedData = updatedData.copyWith(
              capacity: data[0] / 2.5,
              soc: data[2],
              soh: data[3],
              cycles: data[5],
            );
          }
          break;

        case '0x311':
        case '0x312':
        case '0x313':
        case '0x314':
          if (data.length >= 8) {
            int startCell = 0;
            if (id == '0x311') startCell = 0;
            else if (id == '0x312') startCell = 4;
            else if (id == '0x313') startCell = 8;
            else if (id == '0x314') startCell = 12;

            // Cập nhật điện áp cell
            List<double> newCellVoltages = List.from(updatedData.cellVoltages);
            for (int i = 0; i < 4; i++) {
              if (startCell + i < newCellVoltages.length) {
                int cellIndex = startCell + i;
                int byteOffset = i * 2;
                if (data.length > byteOffset + 1) {
                  newCellVoltages[cellIndex] = ((data[byteOffset] << 8) | data[byteOffset + 1]) / 10000.0;
                }
              }
            }

            // Tính toán lại các giá trị cell voltages
            double avgVoltage = 0.0;
            double maxVolt = 0.0;
            double minVolt = double.infinity;
            
            // Chỉ xem xét các cell có điện áp > 0
            List<double> validVoltages = newCellVoltages.where((v) => v > 0).toList();
            if (validVoltages.isNotEmpty) {
              avgVoltage = validVoltages.reduce((a, b) => a + b) / validVoltages.length;
              maxVolt = validVoltages.reduce((a, b) => a > b ? a : b);
              minVolt = validVoltages.reduce((a, b) => a < b ? a : b);
            } else {
              minVolt = 0.0;
            }
            
            double diffVoltage = maxVolt - minVolt;

            updatedData = updatedData.copyWith(
              cellVoltages: newCellVoltages,
              averageVoltage: avgVoltage,
              maxVoltage: maxVolt,
              minVoltage: minVolt,
              voltageDifference: diffVoltage,
            );
          }
          break;

        case '0x31A':
        case '0x31B':
          if (data.length >= 8) {
            int startCell = 0;
            if (id == '0x31A') startCell = 16;
            else if (id == '0x31B') startCell = 20;

            // Cập nhật điện áp cell
            List<double> newCellVoltages = List.from(updatedData.cellVoltages);
            for (int i = 0; i < 4; i++) {
              if (startCell + i < newCellVoltages.length) {
                int cellIndex = startCell + i;
                int byteOffset = i * 2;
                if (data.length > byteOffset + 1) {
                  newCellVoltages[cellIndex] = ((data[byteOffset] << 8) | data[byteOffset + 1]) / 10000.0;
                }
              }
            }

            // Tính toán lại các giá trị cell voltages
            double avgVoltage = 0.0;
            double maxVolt = 0.0;
            double minVolt = double.infinity;
            
            // Chỉ xem xét các cell có điện áp > 0
            List<double> validVoltages = newCellVoltages.where((v) => v > 0).toList();
            if (validVoltages.isNotEmpty) {
              avgVoltage = validVoltages.reduce((a, b) => a + b) / validVoltages.length;
              maxVolt = validVoltages.reduce((a, b) => a > b ? a : b);
              minVolt = validVoltages.reduce((a, b) => a < b ? a : b);
            } else {
              minVolt = 0.0;
            }
            
            double diffVoltage = maxVolt - minVolt;

            updatedData = updatedData.copyWith(
              cellVoltages: newCellVoltages,
              averageVoltage: avgVoltage,
              maxVoltage: maxVolt,
              minVoltage: minVolt,
              voltageDifference: diffVoltage,
            );
          }
          break;

        case '0x321':
          if (data.length >= 4) {
            List<int> newTemperatures = List.filled(4, 0);
            for (int i = 0; i < 4 && i < data.length; i++) {
              newTemperatures[i] = data[i];
            }
            
            updatedData = updatedData.copyWith(
              temperatures: newTemperatures,
            );
          }
          break;
      }

      // Cập nhật dữ liệu mới nhất và trả về
      _latestData = updatedData;
      return updatedData;
    } catch (e) {
      print('Error parsing JSON: $e');
      return _latestData;
    }
  }
} 
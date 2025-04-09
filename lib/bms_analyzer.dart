import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

enum BmsType { ANT, JK, UNKNOWN }

class BmsAnalyzer {
  static BmsType detectBmsType(
      BluetoothDevice device, List<BluetoothService> services) {
    // Kiểm tra tên thiết bị
    String deviceName = device.name.toUpperCase();
    if (deviceName.contains('JK') || deviceName.contains('BMS-JK')) {
      print("Phát hiện JK BMS từ tên thiết bị: $deviceName");
      return BmsType.JK;
    }
    if (deviceName.contains('ANT') || deviceName.contains('BMS-ANT')) {
      print("Phát hiện ANT BMS từ tên thiết bị: $deviceName");
      return BmsType.ANT;
    }

    // Kiểm tra service
    bool hasFFE0 = false;
    bool hasFFF0 = false;

    for (var service in services) {
      String uuid = service.uuid.toString().toUpperCase();
      print("Service UUID: $uuid");

      if (uuid.contains('FFE0')) hasFFE0 = true;
      if (uuid.contains('FFF0')) hasFFF0 = true;
    }

    if (hasFFF0) {
      print("Phát hiện JK BMS (FFF0 service)");
      return BmsType.JK;
    } else if (hasFFE0) {
      print("Phát hiện có thể là ANT BMS hoặc JK BMS (FFE0 service)");
      // Vì có nhiều thiết bị BMS sử dụng JK hơn, ưu tiên JK
      return BmsType.JK;
    }

    // Mặc định thiết bị JK BMS nếu không xác định được
    return BmsType.JK;
  }

  // Đổi từ _calculateCrc thành calculateCrc để làm nó public
  static int calculateCrc(List<int> data, int length) {
    int sum = 0;
    for (int i = 0; i < length; i++) {
      sum += data[i];
    }
    return sum & 0xFF; // Chỉ lấy 1 byte thấp
  }

  // JK BMS Commands - Match the write_register format from main.cpp
  static List<int> createJkBmsCellInfoRequest() {
    // Lệnh yêu cầu thông tin cell (COMMAND_CELL_INFO = 0x96)
    // Frame: AA 55 90 EB 96 01 00 00 00 00 00 00 00 00 00 00 00 00 00 [CRC]
    List<int> command = [
      0xAA, // Start sequence
      0x55,
      0x90,
      0xEB,
      0x96, // COMMAND_CELL_INFO
      0x01, // Length
      0x00, // Value (4 bytes)
      0x00,
      0x00,
      0x00,
      0x00, // Padding (9 bytes)
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
    ];
    // Tính CRC cho 19 byte đầu
    int crc = calculateCrc(command, 19);
    command.add(crc);
    return command;
  }

  static List<int> createJkBmsDeviceInfoRequest() {
    // Lệnh yêu cầu thông tin thiết bị (COMMAND_DEVICE_INFO = 0x97)
    // Frame: AA 55 90 EB 97 01 00 00 00 00 00 00 00 00 00 00 00 00 00 [CRC]
    List<int> command = [
      0xAA, // Start sequence
      0x55,
      0x90,
      0xEB,
      0x97, // COMMAND_DEVICE_INFO
      0x01, // Length
      0x00, // Value (4 bytes)
      0x00,
      0x00,
      0x00,
      0x00, // Padding (9 bytes)
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
    ];
    // Tính CRC cho 19 byte đầu
    int crc = calculateCrc(command, 19);
    command.add(crc);
    return command;
  }

  // ANT BMS Commands (Tạm thời giữ nguyên, sẽ xử lý sau)
  static List<int> createAntBmsDeviceInfoRequest() {
    // Lệnh yêu cầu thông tin thiết bị: 7E A1 02 6C 02 20 58 C4 AA 55
    return [0x7E, 0xA1, 0x02, 0x6C, 0x02, 0x20, 0x58, 0xC4, 0xAA, 0x55];
  }

  static List<int> createAntBmsStatusRequest() {
    // Lệnh yêu cầu trạng thái: 7E A1 01 00 00 BE 18 55 AA 55
    return [0x7E, 0xA1, 0x01, 0x00, 0x00, 0xBE, 0x18, 0x55, 0xAA, 0x55];
  }

  static String bytesToHex(List<int> data) {
    return data
        .map((e) => e.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
  }

  // Helper functions to match ESP32 parsing
  static int _jkGet16Bit(List<int> data, int index) {
    return ((data[index + 1] & 0xFF) << 8) | (data[index] & 0xFF);
  }

  static int _jkGet32Bit(List<int> data, int index) {
    return ((data[index + 3] & 0xFF) << 24) |
        ((data[index + 2] & 0xFF) << 16) |
        ((data[index + 1] & 0xFF) << 8) |
        (data[index] & 0xFF);
  }

  static int _jkGetInt16(List<int> data, int index) {
    int value = _jkGet16Bit(data, index);
    return (value & 0x8000) != 0 ? value - 0x10000 : value;
  }

  static int _jkGetInt32(List<int> data, int index) {
    int value = _jkGet32Bit(data, index);
    return (value & 0x80000000) != 0 ? value - 0x100000000 : value;
  }

  static Map<String, dynamic> parseJkBmsData(List<int> data) {
    if (data.isEmpty) return {};

    try {
      // Tìm header JK BMS (55 AA EB 90 02 for Information)
      for (int i = 0; i < data.length - 5; i++) {
        if (data[i] == 0x55 &&
            data[i + 1] == 0xAA &&
            data[i + 2] == 0xEB &&
            data[i + 3] == 0x90 &&
            data[i + 4] == 0x02) {
          // Đã tìm thấy header cho Information frame
          // Kiểm tra độ dài dữ liệu (thường khoảng 300 bytes)
          if (i + 300 > data.length) {
            print("Dữ liệu không đủ độ dài cho JK BMS Information frame");
            return {};
          }

          Map<String, dynamic> result = {};

          // 1. Cell Voltages (byte 6-69, 32 cells, 2 bytes mỗi cell)
          List<double> cellVoltages = [];
          int cellCount = 0;
          for (int j = 0; j < 32; j++) {
            int cellVoltageRaw = _jkGet16Bit(data, i + 6 + j * 2);
            double cellVoltage = cellVoltageRaw * 0.001; // Coefficient 0.001 V
            if (cellVoltage > 0.5 && cellVoltage < 5.0) {
              cellVoltages.add(cellVoltage);
              cellCount++;
            }
          }
          if (cellVoltages.isNotEmpty) {
            result['cellCount'] = cellCount;
            result['cellVoltages'] = cellVoltages;
            result['maxCellVoltage'] =
                cellVoltages.reduce((a, b) => a > b ? a : b);
            result['minCellVoltage'] =
                cellVoltages.reduce((a, b) => a < b ? a : b);
            result['cellDiff'] =
                result['maxCellVoltage'] - result['minCellVoltage'];
            result['avgCellVoltage'] =
                cellVoltages.reduce((a, b) => a + b) / cellVoltages.length;
          }

          // 2. Cell Resistances (byte 80-143, 32 cells, 2 bytes mỗi cell)
          List<double> cellResistances = [];
          for (int j = 0; j < 32; j++) {
            int cellResistanceRaw = _jkGet16Bit(data, i + 80 + j * 2);
            double cellResistance =
                cellResistanceRaw * 0.001; // Coefficient 0.001 Ohm
            cellResistances.add(cellResistance);
          }
          result['cellResistances'] = cellResistances;

          // 3. Power Tube Temperature (byte 144-145)
          int powerTubeTempRaw = _jkGetInt16(data, i + 144);
          result['mosfetTemp'] = powerTubeTempRaw * 0.1; // Coefficient 0.1 °C

          // 4. Wire Resistance Warning Bitmask (byte 146-149)
          int wireResistanceWarning = _jkGet32Bit(data, i + 146);
          result['wireResistanceWarning'] = wireResistanceWarning;

          // 5. Battery Voltage (byte 150-153)
          int batteryVoltageRaw = _jkGet32Bit(data, i + 150);
          result['voltage'] = batteryVoltageRaw * 0.001; // Coefficient 0.001 V

          // 6. Battery Power (byte 154-157)
          int batteryPowerRaw = _jkGet32Bit(data, i + 154);
          result['power'] = batteryPowerRaw * 0.001; // Coefficient 0.001 W

          // 7. Charge Current (byte 158-161)
          int chargeCurrentRaw = _jkGetInt32(data, i + 158);
          result['current'] = chargeCurrentRaw * 0.001; // Coefficient 0.001 A

          // 8. Temperature Sensor 1 (byte 162-163)
          int temp1Raw = _jkGetInt16(data, i + 162);
          result['temperature1'] = temp1Raw * 0.1; // Coefficient 0.1 °C

          // 9. Temperature Sensor 2 (byte 164-165)
          int temp2Raw = _jkGetInt16(data, i + 164);
          result['temperature2'] = temp2Raw * 0.1; // Coefficient 0.1 °C

          // 10. Errors Bitmask (byte 166-167)
          int errorsBitmask = _jkGet16Bit(data, i + 166);
          result['errorsBitmask'] = errorsBitmask;

          // 11. Balance Current (byte 170-171)
          int balanceCurrentRaw = _jkGetInt16(data, i + 170);
          result['balanceCurrent'] =
              (balanceCurrentRaw * 0.001).abs(); // Coefficient 0.001 A

          // 12. Balancing Action (byte 172)
          int balancingAction = data[i + 172];
          result['balancing'] = balancingAction != 0;

          // 13. State of Charge (SOC) (byte 173)
          result['soc'] = data[i + 173]; // %

          // 14. Remaining Capacity (byte 174-177)
          int remainCapacityRaw = _jkGet32Bit(data, i + 174);
          result['remainCapacity'] =
              remainCapacityRaw * 0.001; // Coefficient 0.001 Ah

          // 15. Nominal Capacity (byte 178-181)
          int nominalCapacityRaw = _jkGet32Bit(data, i + 178);
          result['totalCapacity'] =
              nominalCapacityRaw * 0.001; // Coefficient 0.001 Ah

          // 16. Cycle Count (byte 182-185)
          result['cycles'] = _jkGet32Bit(data, i + 182);

          // 17. Total Cycle Capacity (byte 186-189)
          int totalCycleCapacityRaw = _jkGet32Bit(data, i + 186);
          result['totalCycleCapacity'] =
              totalCycleCapacityRaw * 0.001; // Coefficient 0.001 Ah

          // 18. State of Health (SOH) (byte 190)
          result['soh'] = data[i + 190]; // %

          // 19. Precharge Status (byte 191)
          result['prechargeStatus'] = data[i + 191] != 0;

          // 20. Total Runtime (byte 194-197)
          result['totalRuntime'] = _jkGet32Bit(data, i + 194); // Seconds

          // 21. Charging MOSFET Status (byte 198)
          result['charging'] = data[i + 198] != 0;

          // 22. Discharging MOSFET Status (byte 199)
          result['discharging'] = data[i + 199] != 0;

          // 23. Precharging Status (byte 200)
          result['prechargingStatus'] = data[i + 200] != 0;

          // 24. Temperature Sensor 5 (byte 254-255)
          int temp5Raw = _jkGetInt16(data, i + 254);
          result['temperature5'] = temp5Raw * 0.1; // Coefficient 0.1 °C

          // 25. Temperature Sensor 4 (byte 256-257)
          int temp4Raw = _jkGetInt16(data, i + 256);
          result['temperature4'] = temp4Raw * 0.1; // Coefficient 0.1 °C

          // 26. Temperature Sensor 3 (byte 258-259)
          int temp3Raw = _jkGetInt16(data, i + 258);
          result['temperature3'] = temp3Raw * 0.1; // Coefficient 0.1 °C

          // 27. Emergency Time Countdown (byte 218-219)
          result['emergencyTime'] = _jkGet16Bit(data, i + 218); // Seconds

          // 28. CRC Checksum (byte 299)
          int crcReceived = data[i + 299];
          List<int> frameData = data.sublist(i, i + 299);
          int crcCalculated = calculateCrc(frameData, 299);
          result['crcValid'] = crcReceived == crcCalculated;

          return result;
        }
      }
    } catch (e) {
      print("Lỗi phân tích dữ liệu JK BMS: $e");
    }
    return {};
  }

  static Map<String, dynamic> parseAntBmsData(List<int> data) {
    // Tạm thời giữ nguyên, sẽ xử lý sau
    if (data.isEmpty) return {};

    try {
      for (int i = 0; i < data.length - 4; i++) {
        if (data[i] == 0xAA &&
            data[i + 1] == 0x55 &&
            data[i + 2] == 0x90 &&
            data[i + 3] == 0xEB) {
          if (i + 100 > data.length) {
            print("Dữ liệu không đủ độ dài cho ANT BMS frame");
            return {};
          }

          Map<String, dynamic> result = {};

          if (i + 5 < data.length) {
            int voltageRaw = (data[i + 4] << 8) | data[i + 5];
            result['voltage'] = voltageRaw / 100.0;
          }

          if (i + 7 < data.length) {
            int currentRaw = (data[i + 6] << 8) | data[i + 7];
            result['current'] = (currentRaw > 0x8000)
                ? -((0xFFFF - currentRaw + 1) / 10.0)
                : currentRaw / 10.0;
          }

          if (i + 8 < data.length) {
            result['soc'] = data[i + 8];
          }

          int cellCount = data[i + 9];
          result['cellCount'] = cellCount;

          List<double> cellVoltages = [];
          for (int j = 0; j < cellCount; j++) {
            if (i + 10 + j * 2 + 1 < data.length) {
              int cellVoltageRaw =
                  (data[i + 10 + j * 2] << 8) | data[i + 10 + j * 2 + 1];
              double cellVoltage = cellVoltageRaw / 1000.0;
              if (cellVoltage > 0.5 && cellVoltage < 5.0) {
                cellVoltages.add(cellVoltage);
              }
            }
          }
          if (cellVoltages.isNotEmpty) {
            result['cellVoltages'] = cellVoltages;
            result['maxCellVoltage'] =
                cellVoltages.reduce((a, b) => a > b ? a : b);
            result['minCellVoltage'] =
                cellVoltages.reduce((a, b) => a < b ? a : b);
            result['cellDiff'] =
                result['maxCellVoltage'] - result['minCellVoltage'];
            result['avgCellVoltage'] =
                cellVoltages.reduce((a, b) => a + b) / cellVoltages.length;
          }

          if (i + 53 < data.length) {
            List<double> temperatures = [];
            for (int j = 0; j < 2; j++) {
              int tempRaw =
                  (data[i + 50 + j * 2] << 8) | data[i + 50 + j * 2 + 1];
              double temp = (tempRaw - 2731) / 10.0;
              temperatures.add(temp);
            }
            result['temperature1'] = temperatures[0];
            result['temperature2'] = temperatures[1];
          }

          if (i + 57 < data.length) {
            int remainCapacityRaw = (data[i + 54] << 24) |
                (data[i + 55] << 16) |
                (data[i + 56] << 8) |
                data[i + 57];
            result['remainCapacity'] = remainCapacityRaw / 1000.0;
          }

          return result;
        }
      }
    } catch (e) {
      print("Lỗi phân tích dữ liệu ANT BMS: $e");
    }
    return {};
  }
}

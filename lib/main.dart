import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/data_display_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Scanner',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const BleScanScreen(),
    );
  }
}

class BleScanScreen extends StatefulWidget {
  const BleScanScreen({Key? key}) : super(key: key);

  @override
  State<BleScanScreen> createState() => _BleScanScreenState();
}

class _BleScanScreenState extends State<BleScanScreen> {
  final String SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  final String CHARACTERISTIC_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
  
  List<ScanResult> devices = [];
  bool isScanning = false;
  BluetoothDevice? connectedDevice;
  String receivedData = '';

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    bool allGranted = true;
    statuses.forEach((permission, status) {
      if (!status.isGranted) {
        allGranted = false;
      }
    });

    if (!allGranted) {
      print('Permissions not granted');
      return;
    }
  }

  Future<void> startScan() async {
    setState(() {
      devices.clear();
      isScanning = true;
    });

    try {
      // Listen to scan results
      FlutterBluePlus.scanResults.listen((results) {
        setState(() {
          devices = results;
        });
      });

      // Start scanning
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 4),
        androidUsesFineLocation: true,
      );
    } catch (e) {
      print('Error scanning: $e');
    } finally {
      setState(() {
        isScanning = false;
      });
    }
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      setState(() {
        connectedDevice = device;
      });
      print('Connected to ${device.platformName}');

      // Discover services
      List<BluetoothService> services = await device.discoverServices();
      
      // Find our specific service
      for (BluetoothService service in services) {
        if (service.uuid.toString() == SERVICE_UUID) {
          // Find our specific characteristic
          for (BluetoothCharacteristic characteristic in service.characteristics) {
            if (characteristic.uuid.toString() == CHARACTERISTIC_UUID) {
              // Subscribe to the characteristic
              await characteristic.setNotifyValue(true);
              
              // Create a StreamController for the data
              final dataStreamController = StreamController<String>();
              
              // Listen to notifications and add to stream
              characteristic.onValueReceived.listen((value) {
                setState(() {
                  // Convert bytes to string
                  receivedData = String.fromCharCodes(value);
                  // Add to stream
                  dataStreamController.add(receivedData);
                  print('Received data: $receivedData');
                });
              });

              // Navigate to data display screen
              if (mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => DataDisplayScreen(
                      dataStream: dataStreamController.stream,
                    ),
                  ),
                ).then((_) {
                  // Clean up when returning from data screen
                  dataStreamController.close();
                  disconnect();
                });
              }
              break;
            }
          }
          break;
        }
      }
    } catch (e) {
      print('Error connecting: $e');
    }
  }

  Future<void> disconnect() async {
    if (connectedDevice != null) {
      try {
        await connectedDevice!.disconnect();
        setState(() {
          connectedDevice = null;
          receivedData = '';
        });
      } catch (e) {
        print('Error disconnecting: $e');
      }
    }
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Scanner'),
        actions: [
          if (connectedDevice != null)
            IconButton(
              icon: const Icon(Icons.bluetooth_disabled),
              onPressed: disconnect,
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton(
              onPressed: isScanning ? null : startScan,
              child: Text(isScanning ? 'Đang quét...' : 'Quét thiết bị BLE'),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: devices.length,
              itemBuilder: (context, index) {
                final device = devices[index].device;
                final rssi = devices[index].rssi;
                return ListTile(
                  title: Text(device.platformName.isEmpty 
                    ? 'Unknown Device' 
                    : device.platformName),
                  subtitle: Text('RSSI: $rssi'),
                  trailing: ElevatedButton(
                    onPressed: () => connectToDevice(device),
                    child: const Text('Kết nối'),
                  ),
                );
              },
            ),
          ),
          if (receivedData.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(8.0),
              color: Colors.grey[200],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Dữ liệu nhận được:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(receivedData),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

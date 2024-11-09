import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:convert'; // Để sử dụng Utf8Decoder
import 'dart:typed_data'; // Để sử dụng Uint8List
import 'package:fluttertoast/fluttertoast.dart';
import 'upload.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart'; // Thư viện để chọn tệp


void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => DeviceModel(),  // Cung cấp DeviceModel cho ứng dụng
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: BluetoothScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class BluetoothScreen extends StatefulWidget {
  const BluetoothScreen({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _BluetoothScreenState createState() => _BluetoothScreenState();
}
// BluetoothCharacteristic? commandCharacteristic;
class _BluetoothScreenState extends State<BluetoothScreen> {
  
  List<ScanResult> scanResults = [];
  late StreamSubscription scanSubscritpion;
  late StreamSubscription connectionSubscription;
  
  //late BluetoothCharacteristic commandCharacteristic;
  Timer? sendTimer;
  List<String> receivedData = [];
  Timer? displayTimer;
  

  @override
  void initState() {
    super.initState();
    checkBluetooth();
    
  }
  // Kiểm tra xem có kích thoạt bluetooth chưa 
  Future<void> checkBluetooth() async {
    if (await FlutterBluePlus.isSupported == false) {
      // ignore: avoid_print
      print("Bluetooth not supported by this device");
      return;
    }

    FlutterBluePlus.adapterState.listen((state) {
      // ignore: avoid_print
      print(state);
    });
    // yêu cầu người dùng bật bluetooth 
    if (Platform.isAndroid) {
      await FlutterBluePlus.turnOn();
    }
  }
  // function quét bluetooth
  void startScan() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bắt đầu quét Bluetooth...')),
    );

    scanSubscritpion = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult result in results) {
        // Điều kiện này để tránh việc quét trùng lập các thiết bị bluetooth 
        // ignore: unnecessary_null_comparison
        if (result.advertisementData.advName != null &&
            !scanResults.any((element) => element.device.remoteId == result.device.remoteId)) {
          setState(() {
            scanResults.add(result);
          });
          // in ra các thiết bị bluetooth đã quét được 
          // ignore: avoid_print
          print('${result.device.remoteId}: "${result.advertisementData.advName}" found!');
          // Lưu result.device vào biến toàn cục
          selectedDevice = result.device;
        }
      }
    });
    // quét ble trong vòng 5 giấy 
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    // chờ cho đến khi quá trình quét ble được thực thi xong 
    await FlutterBluePlus.isScanning.where((val) => val == false).first;
    // ignore: use_build_context_synchronously
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Quá trình quét hoàn tất!')),
    );
    // nếu không quét được thiết bị ble nào in ra không quét được thiết bị nào 
    if (scanResults.isEmpty) {
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm thấy thiết bị nào!')),
      );
    }
    // hủy đăng ký tránh việc rò rỉ bộ nhớ 
    scanSubscritpion.cancel();
  }
  
  
  // ignore: non_constant_identifier_names
  
  // ignore: non_constant_identifier_names
  String model_number = '00002a24-0000-1000-8000-00805f9b34fb';
  // ignore: non_constant_identifier_names
  String serial_number = '00002a25-0000-1000-8000-00805f9b34fb';
  String firmwareVersion = '00002a26-0000-1000-8000-00805f9b34fb';
  // ignore: non_constant_identifier_names
  String hw_version = '00002a27-0000-1000-8000-00805f9b34fb';
  String manufacturer = '00002a29-0000-1000-8000-00805f9b34fb';

  
  void discoverBluetoothServices(BluetoothDevice device) async {
    try {
      // Yêu cầu thiết bị khám phá các dịch vụ
      List<BluetoothService> services = await device.discoverServices();
      // Lặp qua các dịch vụ và in ra thông tin
      for (BluetoothService service in services) {
        // UUID dịch vụ cần quan tâm
        if (service.uuid == Guid("00008018-0000-1000-8000-00805f9b34fb"))
        {
          // ignore: avoid_print
          print('pass connect service uuid');
          // Lọc ra đặc tính cần nhận thông báo
          for (BluetoothCharacteristic characteristic in service.characteristics) {
            // ignore: avoid_print
            print('Characteristic UUID: ${characteristic.uuid}');
            if (characteristic.uuid == Guid("00008020-0000-1000-8000-00805f9b34fb"))
            {
              commandCharacteristic  = characteristic;
              print('commandCharacteristic: $commandCharacteristic');
              // ignore: avoid_print
              
              print('pass connect characteristic uuid');
              if (characteristic.properties.notify)
              {
                
                // ignore: avoid_print
                print('Setting up notification for characteristic...');
                await characteristic.setNotifyValue(true);
                // ignore: deprecated_member_use
                characteristic.value.listen((value) {
                  // ignore: avoid_print
                  parseFirmwareNotification(value as ByteData);
                  print('value: $value');
                });
              }
            }
            // Đăng ký nhận thông báo cho đặc tính UUID "00008022-0000-1000-8000-00805f9b34fb"
            if (characteristic.uuid == Guid("00008022-0000-1000-8000-00805f9b34fb")) {
              // ignore: avoid_print
              print('Pass connect characteristic uuid: 8022');
              if (characteristic.properties.notify) {
                await characteristic.setNotifyValue(true);
                // ignore: deprecated_member_use
                characteristic.value.listen((value) {
                  // ignore: avoid_print
                  print('Received command notification: $value');
                  
                  //parseCommandNotification(value);
                });
              }
            }
          }
        }
      }
      // ignore: use_build_context_synchronously
      await readModel(device,model_number,0,context);
      // ignore: use_build_context_synchronously
      await readModel(device,serial_number,1,context);
      // ignore: use_build_context_synchronously
      await readModel(device,firmwareVersion,2,context);
      // ignore: use_build_context_synchronously
      await readModel(device, hw_version,3,context);
      // ignore: use_build_context_synchronously
      await readModel(device, manufacturer,4,context);
    } catch (e) {
      // ignore: avoid_print
      print('Error discovering services: $e');
    }
  }
  // Hàm chính để gửi firmware

  // Hàm chuyển đổi Uint8List (tương đương với ArrayBuffer) thành String
  String ab2str(Uint8List buf) {
    return utf8.decode(buf);
  }
  // ignore: non_constant_identifier_names
  Future<void> readModel(BluetoothDevice device,String MODEL,int number,BuildContext context) async {
    try {
      // Khám phá các dịch vụ của thiết bị
      List<BluetoothService> services = await device.discoverServices();
      // Tìm dịch vụ với UUID 0x180a
      BluetoothService? modelService;
      for (BluetoothService service in services) {
        if (service.uuid == Guid('0000180a-0000-1000-8000-00805f9b34fb')) {
          modelService = service;
          break;
        }
      }
      if (modelService != null) {
        // Tìm đặc tính với UUID 0x2a24
        BluetoothCharacteristic? modelCharacteristic;
        for (BluetoothCharacteristic characteristic in modelService.characteristics) {
          if (characteristic.uuid == Guid(MODEL)) {
            modelCharacteristic = characteristic;
            break;
          }
        }
        if (modelCharacteristic != null) {
          // Đọc giá trị từ đặc tính
          final response = await modelCharacteristic.read().timeout(
            const Duration(milliseconds: 500), // Thời gian chờ 500ms
            onTimeout: () {
              throw TimeoutException("Timeout reading 0x2a24");
            },
          );
          // Chuyển List<int> thành Uint8List và giải mã
          Uint8List uint8ListResponse = Uint8List.fromList(response);  // Chuyển đổi List<int> thành Uint8List
          String model = ab2str(uint8ListResponse);  // Chuyển đổi thành chuỗi
          // ignore: avoid_print
          print("Model: $model");
          // Cập nhật giá trị trong DeviceModel
          // ignore: use_build_context_synchronously
          var deviceModel = Provider.of<DeviceModel>(context, listen: false);
          if(number == 0) {
            deviceModel.updateModelNumber(model);
          } else if(number == 1)
          {
            deviceModel.updateSerialNumber(model);
          }
          else if(number == 2)
          {
            deviceModel.updateFirmwareNumber(model);
          }
          else if(number == 3)
          {
            deviceModel.updateHwVersion(model);
          }
          else if(number == 4)
          {
            deviceModel.updateManufacturer(model);
          }
          // Giả sử bạn có hàm setModel và setDis để cập nhật UI
          setModel(model);  // Cập nhật model
          setDis(true);     // Đánh dấu đã có thông tin
        } else {
          throw Exception("Characteristic 0x2a24 not found");
        }
      } else {
        throw Exception("Service 0x180a not found");
      }
    } catch (error) {
      // ignore: avoid_print
      print("Error reading 0x2a24: $error");
      // Nếu có lỗi, cập nhật model thành chuỗi rỗng và trạng thái disInfo là false
      setModel("");  // Cập nhật model thành chuỗi rỗng
      setDis(false); // Đặt trạng thái disInfo thành false
    }
  }
  // Hàm giả lập cập nhật UI
  void setModel(String model) {
    // ignore: avoid_print
    print("Model updated: $model");
  }

  void setDis(bool disInfo) {
    // ignore: avoid_print
    print("Dis info updated: $disInfo");
  }
  // function kết nối với thiết bị qua tên 
  Future<void> connectToDevice(BluetoothDevice device) async
  {
    try{
      // tắt chế độ tự động kết nối 
      // line connect to bluetooth 
      await device.connect(autoConnect: false);
      // ignore: avoid_print
      print('Connected to ${device.remoteId}');   
      //print('Connected to ${connectedDevice!.advName}');   
      setState(() {
        connectedDevice = device;
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => const MyHomePage(
                    title: 'VERSION 1.0 ANDROID APP',
                  )),
        );
      });
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kết nối với ${device.remoteId} thành công!')),
      );

      if (Platform.isAndroid) {
        try {
          // Yêu cầu MTU là 512 byte
          await device.requestMtu(512);
          // ignore: avoid_print
          print("MTU request sent successfully!");
        } catch (e) {
          // ignore: avoid_print
          print("Failed to request MTU: $e");
        }
      }

      final mtuSubscription = device.mtu.listen((int mtu) {
        // ignore: avoid_print
        print("Current MTU: $mtu");
      });
      // Khám phá dịch vụ sau khi kết nối 
      discoverBluetoothServices(device);
      // thông báo khi thiết bị bị mất kết nối với bluetooth 
      connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          // ignore: avoid_print
          print("Disconnected from ${device.remoteId}");
          reconnectToDevice(device);
          mtuSubscription.cancel();
          sendTimer?.cancel();
        }
      });

      device.cancelWhenDisconnected(connectionSubscription, delayed: true, next: true);

    }catch (e) {
      // nếu kết nối thất bại in ra thông báo kết nối thất bại
      // ignore: avoid_print
      print('Error connecting to device: $e');
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kết nối với ${device.remoteId} thất bại!')),
      );
    }
  }
  // function reconnect lại với thiết bị qua tên 
  Future<void> reconnectToDevice(BluetoothDevice device) async {
    while (true) {
      try {
        await device.connect(autoConnect: false);
        // ignore: avoid_print
        print('Reconnected to ${device.remoteId}');
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kết nối lại với ${device.remoteId} thành công!')),
        );
        break;
      } catch (e) {
        // ignore: avoid_print
        print('Error reconnecting to device: $e');
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }
  @override
  void dispose() {
    displayTimer?.cancel();
    sendTimer?.cancel();
    super.dispose();
  }
  @override
  Widget build(BuildContext context)
  {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text(
          'OTA BLE',
          style: TextStyle(
            color: Color.fromARGB(255, 51, 79, 236),
            fontWeight: FontWeight.bold,
            fontSize: 24,
            fontStyle: FontStyle.italic,
          ),
        )),
      body: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Column(
              children: [
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: startScan,
                  child: const Text(
                    'Bắt đầu quét Bluetooth',
                    style: TextStyle(
                      color: Color.fromARGB(255, 35, 36, 33),
                      fontWeight: FontWeight.bold,
                      fontSize: 30,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.8,
                  child: ListView.builder(
                    itemCount: scanResults.length,
                    itemBuilder: (context, index) {
                      final result = scanResults[index];
                      return ListTile(
                        title: Text(result.device.remoteId.toString()),
                        subtitle: Text(result.advertisementData.advName),
                        onTap: () {
                          connectToDevice(result.device);
                          setState(() {});
                        },
                      );
                    },
                  ),
                ),
                
              ],
            ),
          ],
        ),
      ),
    );
  }
}

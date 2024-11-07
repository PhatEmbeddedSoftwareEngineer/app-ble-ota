import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
bool isFileLoaded = false;
bool showBar = false;
String otaType = "undefined";
bool isConnected = false;
BluetoothDevice? connectedDevice;
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage>
{
  @override
  void initState()
  {
    super.initState();
  }
  @override
  void dispose() {
    super.dispose();
  }
  // Hàm để ngắt kết nối
  void disconnectClick() async {
    setState(() {
      isFileLoaded = false;
      showBar = false;
      otaType = "undefined";
    });

    if (isConnected && connectedDevice != null) {
      setState(() {
        isConnected = false;  // Đặt trạng thái kết nối thành false (ngắt kết nối)
      });

      // Ngắt kết nối với thiết bị Bluetooth
      await connectedDevice!.disconnect();
    }
  }
  @override
  Widget build(BuildContext context)
  {

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(
          widget.title,
          style: const TextStyle(
            color: Color.fromARGB(255, 51, 79, 236), // Màu chữ
            fontWeight: FontWeight.bold, // Làm chữ đậm
            fontSize: 20,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
      body: Consumer<DeviceModel>(
        builder: (context, deviceModel, child){
          return ListView(
            children: [
              const SizedBox(height: 10),
              Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Model Number: ${deviceModel.modelNumber}',
                    style: TextStyle(fontSize: 20),
                  ),
                  Text(
                    'Serial Number: ${deviceModel.serialNumber}',
                    style: TextStyle(fontSize: 20),
                  ),
                  Text(
                    'Firmware Number: ${deviceModel.firmwareNumber}',
                    style: TextStyle(fontSize: 20),
                  ),
                  Text(
                    'HW Version: ${deviceModel.hwVersion}',
                    style: TextStyle(fontSize: 20),
                  ),
                  Text(
                    'Manufacturer: ${deviceModel.manufacturer}',
                    style: TextStyle(fontSize: 20),
                  ),
                ],
              ),
              ElevatedButton(
                onPressed: () {
                  disconnectClick(); // Gọi hàm ngắt kết nối
                  Navigator.pop(context); // Quay lại màn hình trước
                },
                child: const Text("Disconnect"),
              )

            ],
          );
        }
      ),
    );
  }
}



class DeviceModel with ChangeNotifier {
  String _modelNumber = "";
  String _serialNumber = "";
  String _firmwareNumber = "";
  String _hwVersion = "";
  String _manufacturer = "";

  String get modelNumber => _modelNumber;
  String get serialNumber => _serialNumber;
  String get firmwareNumber => _firmwareNumber;
  String get hwVersion => _hwVersion;
  String get manufacturer => _manufacturer;

  // Cập nhật modelNumber
  void updateModelNumber(String model) {
    _modelNumber = model;
    notifyListeners();  // Cập nhật UI khi giá trị thay đổi
  }

  // Cập nhật serialNumber
  void updateSerialNumber(String serial) {
    _serialNumber = serial;
    notifyListeners();
  }

  // Cập nhật firmwareNumber
  void updateFirmwareNumber(String firmware) {
    _firmwareNumber = firmware;
    notifyListeners();
  }

  // Cập nhật hwVersion
  void updateHwVersion(String version) {
    _hwVersion = version;
    notifyListeners();
  }

  // Cập nhật manufacturer
  void updateManufacturer(String manufacturer) {
    _manufacturer = manufacturer;
    notifyListeners();
  }
}



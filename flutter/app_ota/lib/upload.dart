import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';

bool isFileLoaded = false;
bool showBar = false;

BluetoothDevice? connectedDevice;
late BluetoothCharacteristic commandCharacteristic;
late BluetoothDevice? selectedDevice; // Biến toàn cục để lưu device đã chọn
//late final result;
Uint8List? otaFile; // Lưu trữ tệp sau khi chọn
String fileName = ''; // Lưu tên file
List<int> fileBytes = []; // Lưu dữ liệu của file

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}
  int fwStatus = 0;
  int expectedIndex = 1; // Example expected index, adjust as needed
    // CRC 
  int crc16(int init, List<int> data, int len) {
    int crc = init;
    for (int i = 0; i < len; i++) {
      crc ^= data[i] << 8;  // Dịch dữ liệu vào phần CRC
      for (int j = 0; j < 8; j++) {
        if (crc & 0x8000 != 0) {
          crc = ((crc << 1) ^ 0x1021) & 0xFFFF;  // XOR với polynominal CRC-16 crc*2 ^ 0c1021
        } else {
          crc <<= 1;
        }
      }
    }
    return crc & 0xFFFF;  // Đảm bảo CRC luôn trong phạm vi 16 bit
  }
void parseFirmwareNotification(ByteData value) {
    // Check if the byte length is at least 20
    if (value.lengthInBytes >= 20) {
      // Get the CRC value (16-bit unsigned integer at byte index 18)
      int crc = value.getUint16(18, Endian.little);

      // Calculate the received CRC using crc16 function
      List<int> dataBytes = value.buffer.asUint8List(0, 16);
      int crcRecv = crc16(0, dataBytes, 18);

      // Compare the received CRC with the calculated CRC
      if (crcRecv == crc) {
        // Get the firmware answer (fw_ans)
        int fwAns = value.getUint16(2, Endian.little);

        // Check the value of fwAns and handle accordingly
        if (fwAns == 0 && expectedIndex == value.getUint16(0, Endian.little)) {
          fwStatus = 1;
          print("OK");
        } else if (fwAns == 1 && expectedIndex == value.getUint16(0, Endian.little)) {
          fwStatus = 0;
          setStatus("CRC Error");
          print("CRC Error");
          // TODO: Handle CRC error
        } else if (fwAns == 2) {
          fwStatus = 0;
          setStatus("Index Error");
          print("Index Error");
          // TODO: Handle sector index error
        } else if (fwAns == 3 && expectedIndex == value.getUint16(0, Endian.little)) {
          fwStatus = 0;
          setStatus("Payload length Error");
          print("Payload length Error");
          // TODO: Handle payload length error
        }
      }
    }
  }
  void setStatus(String status) {
    print("Status: $status");
  }
class _MyHomePageState extends State<MyHomePage>
{
  String model = '';  // Đây là trạng thái tương đương với `Model` trong React
  late Uint8List databytes;
  int ACK = 1;
  // Các biến trạng thái
  String status = "";
  double progress = 0;
  late bool isConnected;
  late bool isFileLoaded;
  late bool isProgressBarVisible;
  double uploadSpeed = 0.00;
  String barStatus = "danger";
  bool showStatus = false;
  int cmdStatus = 0;
  //int expected_index = 0;
  String otaType = "undefined";

  bool isUploading = false; // Biến trạng thái để kiểm tra quá trình upload
  @override
  void initState()
  {
    super.initState();
  }
  @override
  void dispose() {
    super.dispose();
  }
    // Cập nhật tốc độ tải
  void setUploadSpeed(double speed) {
    setState(() {
      uploadSpeed = speed;
    });
  }
  // Cập nhật trạng thái của thanh tiến trình (bar)
  void setBarStatus(String status) {
    setState(() {
      barStatus = status;
      // Cập nhật trạng thái thanh tiến trình
      print("Bar Status: $status");
    });
  }
  // Hiển thị trạng thái
  void setShowStatus(bool status) {
    setState(() {
      showStatus = status;
    });
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

  
  Future<bool> waitForAnsCommand(int timeoutMillis) async {
    // If the command status is already ACK, resolve immediately with true
    if (cmdStatus == ACK) {
      return true;
    }

    // Define the timeout future
    Future<bool> timeoutFuture = Future.delayed(Duration(milliseconds: timeoutMillis), () {
      print("timeout1");
      return false;
    });

    // Define the periodic check using Timer
    bool result = await Future.any([
      timeoutFuture,
      _checkConditionPeriodically(),
    ]);

    return result;
  }
  Future<bool> _checkConditionPeriodically() async {
    // Use a Timer to check the condition every 50ms
    Completer<bool> completer = Completer();

    Timer? intervalTimer;
    intervalTimer = Timer.periodic(Duration(milliseconds: 50), (timer) {
      if (cmdStatus == ACK) {
        // Stop the interval once the condition is met
        intervalTimer?.cancel();
        completer.complete(true);
      }
    });

    // Wait for the condition to be met or timeout
    return completer.future;
  }
  Future<bool> waitForAnsFw(int timeoutMillis) async {
    // Check the condition initially
    if (fwStatus == 1) {
      return true;
    }

    // Timer to check the condition periexpectedIndex odically (every 50ms)
    Timer? intervalTimer;

    // A completer to handle async result
    Completer<bool> completer = Completer<bool>();

    intervalTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      // Check if condition is met
      if (fwStatus == 1) {
        // If condition is met, cancel the interval and complete the Future with true
        if (!completer.isCompleted) {
          intervalTimer?.cancel();
          completer.complete(true);
        }
      }
    });

    // Timeout timer to reject the Future after the specified time
    Timer timeoutTimer = Timer(Duration(milliseconds: timeoutMillis), () {
      if (!completer.isCompleted) {
        // If timeout occurs, cancel the interval and complete the Future with false
        intervalTimer?.cancel();
        completer.complete(false);
      }
    });

    // Await the result from completer (true or false based on condition or timeout)
    return completer.future;
  }

  Future<void> sendFirmware(int packetSize, Uint8List file, BluetoothDevice device, Function setProgress, Function setUploadSpeed, Function setStartTime) async {
    int writtenSize = 0;
    int index = 0;
    final startTime = DateTime.now().millisecondsSinceEpoch;
    try {
      // Khám phá các dịch vụ của thiết bị Bluetooth
      List<BluetoothService> services = await device.discoverServices();
      BluetoothCharacteristic? firmwareCharacteristic;
      // Lặp qua các dịch vụ và tìm đặc tính cần thiết
      for (BluetoothService service in services) {
        if (service.uuid == Guid("00008018-0000-1000-8000-00805f9b34fb")) {
          print('Found service: 00008018-0000-1000-8000-00805f9b34fb');
          for (BluetoothCharacteristic characteristic in service.characteristics) {
            print('Characteristic UUID: ${characteristic.uuid}');
            if (characteristic.uuid == Guid("00008020-0000-1000-8000-00805f9b34fb")) {
              firmwareCharacteristic = characteristic;
              print('Found firmware characteristic');
              break; // Nếu tìm thấy, thoát khỏi vòng lặp
            }
          }
          if (firmwareCharacteristic != null) break;
        }
      }
      if (firmwareCharacteristic == null) {
        print("Firmware characteristic not found!");
        return;
      }
      // Bắt đầu quá trình gửi firmware
      while (writtenSize < file.length)
      {
        int sectorSize = 0;
        int sequence = 0;
        int crc = 0;
        bool fLast = false;
        List<int> sector = file.sublist(writtenSize, writtenSize + 4096);
        if (sector.isEmpty) break;
        while (sectorSize < sector.length) 
        {
          int toRead = packetSize - 3;
          if (sectorSize + toRead > sector.length) {
            toRead = sector.length - sectorSize;
            fLast = true;
          }
          List<int> sectorData = sector.sublist(sectorSize, sectorSize + toRead);
          sectorSize += toRead;
          if (sectorSize >= 4096) fLast = true;
          // Tính CRC cho dữ liệu
          crc = crc16(crc, Uint8List.fromList(sectorData), sectorData.length);
          if (fLast) sequence = 0xFF;
          // Tạo packet (bao gồm index, sequence và dữ liệu)
          List<int> packet = List<int>.filled(toRead + 3, 0);
          packet[0] = index & 0xFF;
          packet[1] = (index >> 8) & 0xFF;
          packet[2] = sequence;
          for (int i = 0; i < sectorData.length; i++) {
            packet[3 + i] = sectorData[i];
          }
          writtenSize += sectorData.length;
          if (fLast) {
            // Tính CRC cuối cùng
            List<int> crcData = [
              crc & 0xFF,
              (crc >> 8) & 0xFF
            ];
            packet.addAll(crcData);
          }
          // Gửi packet qua Bluetooth
          await firmwareCharacteristic.write(Uint8List.fromList(packet), withoutResponse: false);
          // Nếu là lần gửi cuối (fLast), kiểm tra phản hồi
          if (fLast) {
            int pStatus = ((100 * writtenSize) / file.length).round();
            // Cập nhật tiến độ (tùy vào cách bạn sử dụng)
            print("Progress: $pStatus%");
          }

          sequence++;
          
        }
        index++;
      }
      // Đợi thiết bị xác nhận (nếu cần)
      bool fwAck = await waitForAnsFw(5000);
      if (!fwAck) {
        print("Firmware NACK");
        return;
      }
    }catch (e) {
      print("Error sending firmware: $e");
    }

  }
  Future<void> bleWrite(
    BluetoothDevice device,
    String serviceUuid,
    String characteristicUuid,
    Uint8List data, {
    int retries = 3,
    Duration delay = const Duration(seconds: 2),
  }) async {
    int attempt = 0;
    bool success = false;
    while (attempt < retries && !success) {
      try {
        attempt++;
        print('Attempt $attempt to write data...');
        // Kiểm tra kết nối của thiết bị trước khi thực hiện thao tác
        if (!device.isConnected) {
          print("Device is not connected. Reconnecting...");
          await device.connect();
        }
        // Khám phá các dịch vụ của thiết bị
        List<BluetoothService> services = await device.discoverServices();
        BluetoothService? targetService;
        // Tìm dịch vụ với UUID cụ thể
        for (BluetoothService service in services) {
          if (service.uuid == Guid(serviceUuid)) {
            targetService = service;
            break;
          }
        }
        if (targetService == null) {
          print("Service with UUID $serviceUuid not found.");
          throw Exception("Service not found");
        }
        // Tìm đặc tính trong dịch vụ đã tìm thấy
        BluetoothCharacteristic? targetCharacteristic;
        for (BluetoothCharacteristic characteristic in targetService.characteristics) {
          if (characteristic.uuid == Guid(characteristicUuid)) {
            targetCharacteristic = characteristic;
            break;
          }
        }
        if (targetCharacteristic == null) {
          print("Characteristic with UUID $characteristicUuid not found.");
          throw Exception("Characteristic not found");
        }
        // Gửi dữ liệu vào đặc tính với timeout để tránh treo
        await targetCharacteristic.write(data, withoutResponse: false).timeout(Duration(seconds: 10));
        print("Data written successfully to characteristic $characteristicUuid.");
        // Đọc lại giá trị từ characteristic (có thể để kiểm tra phản hồi)
        List<int> response = await targetCharacteristic.read();
        if (response != null && response.isNotEmpty) {
          print("Received response: $response");
        } else {
          print("No response received from characteristic $characteristicUuid.");
          throw Exception("No response received");
        }
        // Nếu mọi thứ thành công, thoát khỏi vòng lặp retry
        success = true;
      } on TimeoutException catch (e) {
        print("Timeout error in attempt $attempt: $e");
        if (attempt < retries) {
          print("Retrying after ${delay.inSeconds} seconds...");
          await Future.delayed(delay); // Đợi trước khi retry
        } else {
          print("Max retry attempts reached. Aborting.");
        }
      } catch (e) {
        print("Error in attempt $attempt: $e");
        // Kiểm tra số lần retry
        if (attempt < retries) {
          print("Retrying after ${delay.inSeconds} seconds...");
          await Future.delayed(delay); // Đợi trước khi retry
        } else {
          print("Max retry attempts reached. Aborting.");
        }
      }
    }
    if (!success) {
      print("Failed to complete BLE write after $retries attempts.");
      // Thực hiện xử lý thêm ở đây, ví dụ: thông báo lỗi, hủy kết nối, ...
    }
  }
  int startTime = 0;
  void setStartTime() {
    setState(() {
      startTime = DateTime.now().millisecondsSinceEpoch;
    });
    print('Start time: $startTime');
  }
  void writeUInt32LE(List<int> buffer, int offset, int value) {
    buffer[offset] = value & 0xFF;
    buffer[offset + 1] = (value >> 8) & 0xFF;
    buffer[offset + 2] = (value >> 16) & 0xFF;
    buffer[offset + 3] = (value >> 24) & 0xFF;
  }
  void writeUInt16LE(List<int> buffer, int offset, int value) {
    buffer[offset] = value & 0xFF;
    buffer[offset + 1] = (value >> 8) & 0xFF;
  }

  Future<void> otaClick() async {
  if (databytes == null) 
  {
    print('cút');
    return;
  }
  onFileLoadUpdate(false);
  otaType="app";
  // Tạo buffer để gửi dữ liệu
  List<int> buffer = List<int>.filled(20, 0);
  print("Start ${otaType} OTA");

  // Kiểm tra otaType để chọn loại OTA phù hợp
  buffer.fillRange(0, 20, 0);
    buffer[0] = 0x01;
    buffer[1] = 0x00;
  if(databytes != null)
  {
    // Ghi kích thước tệp OTA vào buffer (vị trí 2-5)
    writeUInt32LE(buffer, 2, databytes.length);
  }
  // Tính CRC của buffer từ 0 -> 18
  int crc = crc16(0, Uint8List.fromList(buffer.sublist(0, 18)), 18);
  writeUInt16LE(buffer, 18, crc);
  print('buffer: $buffer');
  // Đặt cmdStatus là 0 trước khi gửi
  cmdStatus = 0;
  // Tìm và gửi dữ liệu qua đặc tính Bluetooth
  BluetoothCharacteristic? firmwareCharacteristic;
  List<BluetoothService> services = await connectedDevice!.discoverServices();

  // Lặp qua các dịch vụ và tìm đặc tính firmware
  for (BluetoothService service in services) {
    if (service.uuid == Guid("00008018-0000-1000-8000-00805f9b34fb")) {
      print('Found service: 00008018-0000-1000-8000-00805f9b34fb');
      for (BluetoothCharacteristic characteristic in service.characteristics) {
        if (characteristic.uuid == Guid("00008022-0000-1000-8000-00805f9b34fb")) {
          firmwareCharacteristic = characteristic;
          print('Found firmware characteristic');
          break;  // Nếu tìm thấy, thoát khỏi vòng lặp
        }
      }
      if (firmwareCharacteristic != null) break;
    }
  }

  // Nếu không tìm thấy đặc tính firmware, thông báo lỗi
  if (firmwareCharacteristic == null) {
    print("Firmware characteristic not found");
    return;
  }

  // Gửi dữ liệu qua đặc tính Bluetooth
  await firmwareCharacteristic.write(Uint8List.fromList(buffer));

  // Đợi xác nhận từ thiết bị
  bool cmdAck = await waitForAnsCommand(5000);
  if (!cmdAck) {
    setBarStatus("danger");
    setShowStatus(true);
    print("NACK");
    return;
  }

  print("cmd acked");

  // Cập nhật tiến độ OTA
  onProgressUpdate(0);
  onProgressBarVisibilityChange(true);

  // Gửi firmware
  await sendFirmware(510, databytes!, connectedDevice!, onProgressUpdate, setUploadSpeed, setStartTime);
  print("Stop OTA");

  // Dọn dẹp buffer để gửi tín hiệu kết thúc OTA
  buffer.fillRange(0, 20, 0);
  buffer[0] = 0x02;
  buffer[1] = 0x00;

  // Tính lại CRC cho tín hiệu kết thúc
  crc = crc16(0, Uint8List.fromList(buffer.sublist(0, 18)), 18);
  writeUInt16LE(buffer, 18, crc);

  print(buffer);

  // Gửi tín hiệu kết thúc OTA
  cmdStatus = 0;
  await firmwareCharacteristic.write(Uint8List.fromList(buffer));

  // Đợi xác nhận từ thiết bị
  cmdAck = await waitForAnsCommand(5000);
  if (!cmdAck) {
    setBarStatus("danger");
    setShowStatus(true);
    print("NACK");
    return;
  }

  // Kết thúc OTA
  onOtaTypeUpdate("undefined");
  onConnectionUpdate(false);
  onProgressBarVisibilityChange(false);
  onFileLoadUpdate(false);
  setStatus("OTA Done");
  setBarStatus("success");
  setShowStatus(true);

  // Ngắt kết nối Bluetooth
  await connectedDevice?.disconnect();
}

Future<void> onFileChange() async {
  try {
    // Mở hộp thoại để người dùng chọn tệp
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['bin']);

    if (result != null && result.files.isNotEmpty) {
      String? filePath = result.files.single.path;
      if (filePath == null) {
        print("Lỗi: Không thể lấy đường dẫn tệp.");
        return;
      }

      // Mở tệp từ đường dẫn và kiểm tra kích thước
      File file = File(filePath);
      if (await file.exists()) {
        setState(() {
          fileName = result.files.single.name; // Lưu tên file
          isFileLoaded = true;
          //otaFile = file as Uint8List?; // Gán tệp vào otaFile
        });

        fileBytes = await file.readAsBytes();
        if (fileBytes.length == await file.length()) {
          print("Đã đọc đầy đủ dữ liệu của tệp.");
        } else {
          print("Lỗi: Số byte đọc được không khớp với kích thước tệp.");
        }

        print("Dữ liệu tệp đã được tải xong. Kích thước dữ liệu: ${fileBytes.length} byte(s)");

        databytes = Uint8List.fromList(fileBytes);

        print('chiều dài của data là: ${fileBytes.length}');
        
        // Gọi hàm otaClick để bắt đầu quá trình OTA
        await otaClick();
      } else {
        print("Lỗi: Tệp không tồn tại hoặc không hợp lệ.");
      }
    } else {
      // Người dùng đã huỷ việc chọn tệp
      print("Người dùng đã huỷ việc chọn tệp.");
    }
  } catch (e) {
    // Xử lý ngoại lệ nếu có lỗi trong quá trình chọn tệp hoặc mở tệp
    print("Lỗi khi chọn hoặc mở tệp: $e");
  }
}

  Future<void> printBytesEvery100ms(Uint8List data) async {
    // Chia dữ liệu thành các khối 100 bytes
    const int chunkSize = 510;  // Kích thước mỗi khối 100 bytes
    int totalChunks = (data.length / chunkSize).ceil();  // Số lượng khối dữ liệu
    // Sử dụng Timer để in từng khối mỗi 10ms
    for (int i = 0; i < totalChunks; i++) {
      int start = i * chunkSize;
      int end = (start + chunkSize <= data.length) ? start + chunkSize : data.length;
      // Cắt ra một phần dữ liệu (chunk)
      List<int> chunk = data.sublist(start, end);
      // In ra khối dữ liệu dưới dạng hex
      print("Khối dữ liệu từ ${start} đến ${end}: ${chunk.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}");
      // Chờ 100ms trước khi in khối tiếp theo
      await Future.delayed(Duration(milliseconds: 10));
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
              ),
              // Nút chọn tệp
              ElevatedButton(
                onPressed: onFileChange,
                child: const Text("Chọn tệp OTA"),
              ),
              ElevatedButton(
                onPressed: () async {
                    // Kiểm tra nếu không có thiết bị kết nối
                    if (connectedDevice == null) {
                      Fluttertoast.showToast(msg: "Chưa có thiết bị kết nối");
                      return;
                    }
                    // Kiểm tra nếu tệp OTA không được tải lên
                    if (databytes.isEmpty) {
                      Fluttertoast.showToast(msg: "Chưa chọn tệp OTA");
                      return;
                    }
                    otaClick();
                },
                child: const Text("Up OTA"),
              ),
            ],
          );
        }
      ),
    );
  }
  // Các callback để cập nhật UI hoặc trạng thái trong quá trình OTA
  void onProgressUpdate(double progress) {
    setState(() {
      this.progress = progress;
    });
  }
  void onProgressBarVisibilityChange(bool isVisible) {
    setState(() {
      this.isProgressBarVisible = isVisible;
    });
  }
  void onStatusUpdate(String status) {
    setState(() {
      this.status = status;
    });
  }
  void onBarStatusUpdate(String barStatus) {
    setState(() {
      this.status = barStatus;
    });
  }
  void onShowStatusUpdate(bool showStatus) {
    setState(() {
      // Thực hiện điều gì đó khi cần hiển thị thông báo
      this.showStatus = showStatus;
    });
  }
  void onConnectionUpdate(bool isConnected) {
    setState(() {
      // Cập nhật trạng thái kết nối Bluetooth
      this.isConnected = isConnected;
    });
  }
  void onFileLoadUpdate(bool isFileLoaded) {
    setState(() {
      // Cập nhật trạng thái tải file
      this.isFileLoaded = isFileLoaded;
    });
  }
  void onOtaTypeUpdate(String otaType) {
    setState(() {
      // Cập nhật loại OTA
      this.otaType = otaType;
    });
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



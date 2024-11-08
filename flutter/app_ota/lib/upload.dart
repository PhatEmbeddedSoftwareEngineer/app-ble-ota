import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:crc32_checksum/crc32_checksum.dart';

bool isFileLoaded = false;
bool showBar = false;

bool isConnected = false;
BluetoothDevice? connectedDevice;
late BluetoothCharacteristic commandCharacteristic;

Uint8List? otaFile; // Lưu trữ tệp sau khi chọn
String fileName = ''; // Lưu tên file
List<int> fileBytes = []; // Lưu dữ liệu của file

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage>
{
  String model = '';  // Đây là trạng thái tương đương với `Model` trong React
  bool disInfo = false;  // Đây là trạng thái tương đương với `DISInfo` trong React
  late Uint8List databytes;
  int ACK = 1;
  // Các biến trạng thái
  String status = "";
  double progress = 0;
  late bool isConnected;
  late bool isFileLoaded;
  double uploadSpeed = 0.00;
  String barStatus = "danger";
  bool showStatus = false;
  int cmdStatus = 0;
  int expected_index = 0;
  String otaType = "undefined";
  int fwStatus = 0;
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
  void setProgressBar(bool value) {
    setState(() {
      showBar = value;
    });
  }
  
  void setStatus(String value) {
    // ignore: avoid_print
    print('Status: $status');
    setState(() {
      status = value;
    });
  }
  void setConnection(bool value) {
    setState(() {
      isConnected = value;
    });
  }
  void setLoadFile(bool value) {
    setState(() {
      isFileLoaded = value;
    });
  }

  void setOtaType(String value) {
    setState(() {
      otaType = value;
    });
  }
  Future<bool> waitForAnsCommand(int timeout) async {
    // Nếu cmdStatus đã là ACK ngay từ đầu, trả về true ngay lập tức
    if (cmdStatus == ACK) {
      return true;
    }
    // Tạo một Completer để quản lý Future
    Completer<bool> completer = Completer<bool>();
    // Khởi tạo một biến intervalId nếu cần thiết
    late Timer intervalTimer;

    // Hàm kiểm tra điều kiện
    void checkCondition() {
      if (cmdStatus == ACK) {
        // Nếu trạng thái đã thành công, dừng timer và trả về true
        intervalTimer.cancel();
        completer.complete(true);  // Hoàn thành Future và trả về true
      }
    }

    // Kết thúc sau timeout nếu không có ACK
    Future.delayed(Duration(milliseconds: timeout), () {
      if (!completer.isCompleted) {
        intervalTimer.cancel();  // Nếu chưa hoàn thành, hủy Timer
        print('timeout1');
        completer.complete(false);  // Hoàn thành Future và trả về false
      }
    });

    // Kích hoạt Timer để kiểm tra điều kiện sau mỗi 100ms (hoặc lâu hơn tùy vào yêu cầu)
    intervalTimer = Timer.periodic(Duration(milliseconds: 100), (timer) {
      checkCondition();
    });

    return completer.future;
  }

  Future<bool> waitForAnsFw(int timeoutMillis) async {
    // Kiểm tra điều kiện ban đầu
    if (fwStatus == 1) {
      return true;  // Nếu trạng thái firmware là 1, trả về true ngay lập tức
    }
    // Tạo một StreamController để kiểm tra điều kiện theo chu kỳ
    final StreamController<bool> controller = StreamController<bool>();
    // Kiểm tra điều kiện mỗi 50ms
    Timer? intervalTimer;
    intervalTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (fwStatus == 1) {
        // Nếu điều kiện đã thỏa mãn (fwStatus == 1), dừng timer và trả về true
        if (!controller.isClosed) {
          controller.add(true);
          controller.close();
        }
        intervalTimer?.cancel(); // Hủy timer
      }
    });
    // Tạo một timer cho timeout
    Timer timeoutTimer = Timer(Duration(milliseconds: timeoutMillis), () {
      if (!controller.isClosed) {
        controller.add(false); // Nếu hết thời gian, trả về false
        controller.close();
      }
      intervalTimer?.cancel(); // Hủy timer kiểm tra
    });
    // Chờ kết quả từ StreamController (true hoặc false)
    bool result = await controller.stream.first;
    // Hủy timer timeout nếu đã hoàn tất
    timeoutTimer.cancel();
    return result;
  }
  Future<void> sendFirmware(int packetSize, Uint8List file, BluetoothDevice device, 
    Function setProgress, Function setUploadSpeed, Function setStartTime
  ) async {
    int writtenSize = 0;
    int index = 0;
    final startTime = DateTime.now().millisecondsSinceEpoch;
    while (writtenSize < file.length) {
      if (!connectedDevice!.isConnected) {
        // Thử kết nối lại
        await connectedDevice!.connect();
        if (connectedDevice!.isConnected) {
          print("Kết nối lại thành công!");
        } else {
          print("Không thể kết nối lại!");
        }
      }

      int sectorSize = 0;
      int sequence = 0;
      int crc = 0;
      bool fLast = false;
      // Lấy sector 4096 byte (hoặc ít hơn nếu không đủ)
      List<int> sector = file.sublist(writtenSize, writtenSize + 4096 > file.length ? file.length : writtenSize + 4096);
      if (sector.isEmpty) {
        break;
      }
      while (sectorSize < sector.length) {
        int toRead = packetSize - 3;
        if (sectorSize + toRead > sector.length) {
          toRead = sector.length - sectorSize;
          fLast = true;
        }
        List<int> sectorData = sector.sublist(sectorSize, sectorSize + toRead);
        sectorSize += toRead;
        if (sectorSize >= 4096) fLast = true;
        crc = crc16(crc, Uint8List.fromList(sectorData), sectorData.length);
        if (fLast) sequence = 0xff;
        List<int> packet = [index & 0xFF, (index >> 8) & 0xFF, sequence];
        packet.addAll(sectorData);
        writtenSize += sectorData.length;
        if (fLast) {
          // Cập nhật tiến trình
          int pStatus = ((100 * writtenSize) / file.length).toInt();
          setProgress(pStatus);
          setUploadSpeed(writtenSize * 1000 / 1024 / (DateTime.now().millisecondsSinceEpoch - startTime));

          List<int> crcData = [crc & 0xFF, (crc >> 8) & 0xFF];
          packet.addAll(crcData);
        }
        // Gửi gói OTA
        await bleWrite(device, "00008018-0000-1000-8000-00805f9b34fb", "00008020-0000-1000-8000-00805f9b34fb", Uint8List.fromList(packet));
        // Chờ phản hồi nếu là gói cuối
        if (fLast) {
          bool fwAck = await waitForAnsFw(5000);
          if (!fwAck) {
            print("FW NACK");
            setBarStatus("danger");
            setShowStatus(true);
            return;
          }
        }
        sequence++;
        index++;
      }
    }
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
  // CONVERT BINARY TO UTF
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

  Future<void> bleWrite(BluetoothDevice device,String serviceUuid,String characteristicUuid,Uint8List data,
) async {
    try {
      // Khám phá các dịch vụ của thiết bị
      List<BluetoothService> services = await device.discoverServices();
      // Tìm dịch vụ với UUID cụ thể
      BluetoothService? targetService;
      for (BluetoothService service in services) {
        if (service.uuid == Guid(serviceUuid)) {
          targetService = service;
          break;
        }
      }
      if (targetService == null) {
        print("Service with UUID $serviceUuid not found.");
        return;
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
        return;
      }
      // Gửi dữ liệu vào đặc tính
      await targetCharacteristic.write(data,withoutResponse: false).timeout(Duration(seconds: 10)); // Tăng lên 10 giây hoặc lâu hơn
      print("Data written successfully to characteristic $characteristicUuid.");
      // Nếu cần, bạn có thể đọc lại giá trị hoặc xử lý thêm ở đây
    } catch (e) {
      print("Error in bleWrite: $e");
    }
  }
  int startTime = 0;
  void setStartTime() {
    setState(() {
      startTime = DateTime.now().millisecondsSinceEpoch;
    });
    print('Start time: $startTime');
  }
  Future<void> otaClick(BluetoothDevice device,String otaType, Uint8List otaFile, Function setProgress, 
    Function setProgressBar, Function setStatus, Function setBarStatus, Function setShowStatus, 
    Function setConnection, Function setLoadFile, Function setOtaType, 
) async {
  try {
    // Mặc định otaType là 'app' nếu không có giá trị
    otaType = 'app';  
    if (otaFile.isEmpty) return;
    // Bước 1: Khởi tạo thông báo
    setLoadFile(false);
    List<int> buffer = List.filled(20, 0);
    
    if (otaType == "app") {
      print("Start App OTA");
      buffer[0] = 0x01;
      buffer[1] = 0x00;
    } else if (otaType == "spiffs") {
      print("Start SPIFFS OTA");
      buffer[0] = 0x04;
      buffer[1] = 0x00;
    }
    // Tạo ByteData để chứa giá trị Uint32
    ByteData byteData = ByteData(4);
    byteData.setUint32(0, otaFile.length);
    // Chuyển ByteData thành Uint8List
    Uint8List uint8List = byteData.buffer.asUint8List();
    // Sử dụng setRange để sao chép dữ liệu từ uint8List vào buffer
    buffer.setRange(2, 6, uint8List);
    // Tính CRC
    int crc = crc16(0, Uint8List.fromList(buffer), 18);
    buffer[18] = crc & 0xFF;
    buffer[19] = (crc >> 8) & 0xFF;
    // Gửi gói khởi tạo OTA
    await bleWrite(device, "00008018-0000-1000-8000-00805f9b34fb", "00008022-0000-1000-8000-00805f9b34fb", Uint8List.fromList(buffer));
    // Bước 2: Chờ ACK từ thiết bị
    bool cmdAck = await waitForAnsCommand(5000);
    if (!cmdAck) {
      setBarStatus("danger");
      setShowStatus(true);
      print("NACK");
      return;
    }
    print("cmd acked");

    // Bước 3: Tiến hành gửi các gói OTA
    setProgress(0);
    setProgressBar(true);
    
    await sendFirmware(510, otaFile, device, setProgress, setUploadSpeed, setStartTime);

    // Bước 4: Gửi gói kết thúc OTA
    buffer.fillRange(0, buffer.length, 0);
    buffer[0] = 0x02;
    buffer[1] = 0x00;
    crc = crc16(0, Uint8List.fromList(buffer), 18);
    buffer[18] = crc & 0xFF;
    buffer[19] = (crc >> 8) & 0xFF;

    // Gửi gói kết thúc OTA
    await bleWrite(device, "00008018-0000-1000-8000-00805f9b34fb", "00008022-0000-1000-8000-00805f9b34fb", Uint8List.fromList(buffer));
    
    // Chờ ACK
    cmdAck = await waitForAnsCommand(5000);
    if (!cmdAck) {
      setBarStatus("danger");
      setShowStatus(true);
      print("NACK");
      return;
    }

    // Bước 5: Kết thúc
    setOtaType("undefined");
    setConnection(false);
    setProgressBar(false);
    setLoadFile(false);
    setStatus("OTA Done");
    setBarStatus("success");
    setShowStatus(true);
    await connectedDevice?.disconnect(); // Đảm bảo rằng connectedDevice là một đối tượng BluetoothDevice đã kết nối.

  } catch (e) {
    print("Error in otaClick: $e");
  }
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
  late bool isProgressBarVisible=false;
  Future<void> onFileChange() async {
    try {
      // Mở hộp thoại để người dùng chọn tệp
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['bin']);

      // Kiểm tra xem người dùng có chọn tệp hay không
      if (result != null && result.files.isNotEmpty) {
        // Lấy đường dẫn của tệp đã chọn
        String? filePath = result.files.single.path;
        if (filePath == null) {
          // ignore: avoid_print
          print("Lỗi: Không thể lấy đường dẫn tệp.");
          return;
        }
        // Mở tệp từ đường dẫn và kiểm tra kích thước
        File file = File(result.files.single.path!);

        // Kiểm tra xem tệp có tồn tại không
        if (await file.exists()) {
          setState(() {
            fileName = result.files.single.name; // Lưu tên file
            isFileLoaded = true;
          });
          // Đọc nội dung tệp (nếu cần thiết, bạn có thể thay đổi cách đọc tệp tùy theo yêu cầu của bạn)
          fileBytes = await file.readAsBytes();
          // Kiểm tra xem số byte đọc được có khớp với kích thước tệp hay không
          int fileSize = await file.length();


          if (fileBytes.length == fileSize) {
            print("Đã đọc đầy đủ dữ liệu của tệp.");
          } else {
            print("Lỗi: Số byte đọc được không khớp với kích thước tệp.");
          }
          print("Dữ liệu tệp đã được tải xong. Kích thước dữ liệu: ${fileBytes.length} byte(s)");
          //print('nội dung của tệp là: $fileBytes');
          // Tiến hành xử lý dữ liệu tệp tại đây
          // In dữ liệu ra console theo từng phần nhỏ (khối dữ liệu)
          const int chunkSize = 256; // Kích thước khối dữ liệu (bytes)
          for (int i = 0; i < fileBytes.length; i += chunkSize) {
            // Lấy một phần nhỏ của mảng dữ liệu
            int end = (i + chunkSize < fileBytes.length) ? i + chunkSize : fileBytes.length;
            List<int> chunk = fileBytes.sublist(i, end);
            print("Khối dữ liệu từ $i đến $end: ${chunk.map((e) => e.toRadixString(16)).join(' ')}");
          }
          // Nếu bạn muốn lưu lại dữ liệu vào mảng để truyền qua OTA, có thể sử dụng:
          databytes = Uint8List.fromList(fileBytes);
          print('Dữ liệu đã được lưu vào databytes: ${databytes.length} bytes');
          // Gọi hàm in dữ liệu từng khối nhỏ mỗi 100ms
          await printBytesEvery100ms(databytes);
        } else {
          print("Lỗi: Tệp không tồn tại hoặc không hợp lệ.");
        }
        databytes = Uint8List.fromList(fileBytes);
        
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
  const int chunkSize = 100;  // Kích thước mỗi khối 100 bytes
  int totalChunks = (data.length / chunkSize).ceil();  // Số lượng khối dữ liệu

  // Sử dụng Timer để in từng khối mỗi 100ms
  for (int i = 0; i < totalChunks; i++) {
    int start = i * chunkSize;
    int end = (start + chunkSize <= data.length) ? start + chunkSize : data.length;

    // Cắt ra một phần dữ liệu (chunk)
    List<int> chunk = data.sublist(start, end);

    // In ra khối dữ liệu dưới dạng hex
    print("Khối dữ liệu từ ${start} đến ${end}: ${chunk.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}");

    // Chờ 100ms trước khi in khối tiếp theo
    await Future.delayed(Duration(milliseconds: 100));
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
                    try {
                      // Tiến hành OTA
                      await otaClick(
                        connectedDevice!,
                        'app', // Loại OTA, có thể là 'app' hoặc 'spiffs' tùy vào loại firmware
                        databytes,
                        onProgressUpdate,
                        onProgressBarVisibilityChange,
                        onStatusUpdate,
                        onBarStatusUpdate,
                        onShowStatusUpdate,
                        onConnectionUpdate,
                        onFileLoadUpdate,
                        onOtaTypeUpdate,
                      );
                    } catch (e) {
                      Fluttertoast.showToast(msg: "Có lỗi trong quá trình OTA: $e");
                      print("Lỗi OTA: $e");
                    }

                },
                child: const Text("up"),
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



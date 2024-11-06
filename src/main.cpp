#include <Arduino.h>
#include <BLEServer.h>
#include "ota_ble/BLEOTA.h"
// #include "ota_ble/ota_ble.hpp"

// ota_ble ota;

#define MODEL "1"
#define SERIAL_NUM "1234"
#define FW_VERSION "1.0.0"
#define HW_VERSION "1"
#define MANUFACTURER "Espressif"

BLEOTAClass BLEOTA;
BLEServer* pServer = NULL;

bool deviceConnected = false;
bool oldDeviceConnected = false;
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer, esp_ble_gatts_cb_param_t* param) {
    deviceConnected = true;
    pServer->updateConnParams(param->connect.remote_bda, 0x06, 0x12, 0, 2000);
  };

  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
  }
};



void setup() {
  Serial.begin(115200);

  // Create the BLE Device
  BLEDevice::init("TEST ESP32S3");

  // Create the BLE Server
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  // Add OTA Service
  BLEOTA.begin(pServer);
#ifdef MODEL
  BLEOTA.setModel(MODEL);
#endif
#ifdef SERIAL_NUM
  BLEOTA.setSerialNumber(SERIAL_NUM);
#endif
#ifdef FW_VERSION
  BLEOTA.setFWVersion(FW_VERSION);
#endif
#ifdef HW_VERSION
  BLEOTA.setHWVersion(HW_VERSION);
#endif
#ifdef MANUFACTURER
  BLEOTA.setManufactuer(MANUFACTURER);
#endif

  BLEOTA.init();
  // Start advertising
  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(BLEOTA.getBLEOTAuuid());
  pAdvertising->setScanResponse(false);
  pAdvertising->setMinPreferred(0x0);  // set value to 0x00 to not advertise this parameter
  BLEDevice::startAdvertising();

#ifdef FW_VERSION
  Serial.print("Firmware Version: ");
  Serial.println(FW_VERSION);
#endif

  Serial.println("Waiting a client connection...");
  printf("hello world\n");
}

void loop() {
  // ota.display();
  if (!deviceConnected && oldDeviceConnected) {
    delay(500);                   // give the bluetooth stack the chance to get things ready
    pServer->startAdvertising();  // restart advertising
    Serial.println("start advertising");
    oldDeviceConnected = deviceConnected;
  }
  // connecting
  if (deviceConnected && !oldDeviceConnected) {
    oldDeviceConnected = deviceConnected;
  }
  BLEOTA.process();
  delay(1000);
}


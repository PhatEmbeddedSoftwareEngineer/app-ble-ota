#ifndef OTA_BLE_HPP
#define OTA_BLE_HPP

#include <Arduino.h>
#include <vector>

#define BAUD_DEBUG              115200

class ota_ble
{
public:
    ota_ble(int baud = BAUD_DEBUG);
    ~ota_ble();
    void display();
private:
    int _baud;
    std::vector<int> data;
};

#endif
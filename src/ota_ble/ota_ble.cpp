#include "ota_ble.hpp"

ota_ble::ota_ble(int baud): _baud(baud)
{
    Serial.begin(this->_baud);
}

ota_ble::~ota_ble(){}

void ota_ble::display()
{
    static int count=0;
}


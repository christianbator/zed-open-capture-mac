//
// zed_video_capture.mm
// zed-open-capture-mac
//
// Created by Christian Bator on 01/11/2025
//

#include "../include/zed_video_capture.h"
#import "ZEDVideoCapture.h"

using namespace std;
using namespace zed;

namespace zed {

    struct VideoCaptureImpl {
        ZEDVideoCapture* wrapped;

        VideoCaptureImpl() {
            wrapped = [[ZEDVideoCapture alloc] init];
        };
    };

    VideoCapture::VideoCapture() {
        impl = new VideoCaptureImpl();
    }

    VideoCapture::~VideoCapture() {
        if (impl) {
            delete impl;
        }
    }

    string VideoCapture::getDeviceID() {
        string deviceID = [impl->wrapped.deviceID UTF8String];
        return deviceID;
    }

    string VideoCapture::getDeviceName() {
        string deviceName = [impl->wrapped.deviceName UTF8String];
        return deviceName;
    }

    string VideoCapture::getDeviceSerialNumber() {
        string deviceSerialNumber = [impl->wrapped.deviceSerialNumber UTF8String];
        return deviceSerialNumber;
    }

    uint16_t VideoCapture::getBrightness() {
        return impl->wrapped.brightness;
    }

    void VideoCapture::setBrightness(uint16_t brightness) {
        assert(brightness >= 0 && brightness <= 8);
        [impl->wrapped setBrightness:brightness];
    }

    uint16_t VideoCapture::getDefaultBrightness() {
        return impl->wrapped.defaultBrightness;
    }

    void VideoCapture::resetBrightness() {
        [impl->wrapped resetBrightness];
    }

    uint16_t VideoCapture::getContrast() {
        return impl->wrapped.contrast;
    }

    void VideoCapture::setContrast(uint16_t contrast) {
        assert(contrast >= 0 && contrast <= 8);
        [impl->wrapped setContrast:contrast];
    }

    uint16_t VideoCapture::getDefaultContrast() {
        return impl->wrapped.defaultContrast;
    }

    void VideoCapture::resetContrast() {
        [impl->wrapped resetContrast];
    }

    uint16_t VideoCapture::getHue() {
        return impl->wrapped.hue;
    }

    void VideoCapture::setHue(uint16_t hue) {
        assert(hue >= 0 && hue <= 11);
        [impl->wrapped setHue:hue];
    }

    uint16_t VideoCapture::getDefaultHue() {
        return impl->wrapped.defaultHue;
    }

    void VideoCapture::resetHue() {
        [impl->wrapped resetHue];
    }

    uint16_t VideoCapture::getSaturation() {
        return impl->wrapped.saturation;
    }

    void VideoCapture::setSaturation(uint16_t saturation) {
        assert(saturation >= 0 && saturation <= 8);
        [impl->wrapped setSaturation:saturation];
    }

    uint16_t VideoCapture::getDefaultSaturation() {
        return impl->wrapped.defaultSaturation;
    }

    void VideoCapture::resetSaturation() {
        [impl->wrapped resetSaturation];
    }

    uint16_t VideoCapture::getSharpness() {
        return impl->wrapped.sharpness;
    }

    void VideoCapture::setSharpness(uint16_t sharpness) {
        assert(sharpness >= 0 && sharpness <= 8);
        [impl->wrapped setSharpness:sharpness];
    }

    uint16_t VideoCapture::getDefaultSharpness() {
        return impl->wrapped.defaultSharpness;
    }

    void VideoCapture::resetSharpness() {
        [impl->wrapped resetSharpness];
    }

    uint16_t VideoCapture::getWhiteBalanceTemperature() {
        return impl->wrapped.whiteBalanceTemperature;
    }

    void VideoCapture::setWhiteBalanceTemperature(uint16_t whiteBalanceTemperature) {
        assert(whiteBalanceTemperature >= 2800 && whiteBalanceTemperature <= 6500 && (whiteBalanceTemperature % 100 == 0));
        [impl->wrapped setWhiteBalanceTemperature:whiteBalanceTemperature];
    }

    uint16_t VideoCapture::getDefaultWhiteBalanceTemperature() {
        return impl->wrapped.defaultWhiteBalanceTemperature;
    }

    void VideoCapture::resetWhiteBalanceTemperature() {
        [impl->wrapped resetWhiteBalanceTemperature];
    }

    bool VideoCapture::getAutoWhiteBalanceTemperature() {
        return impl->wrapped.autoWhiteBalanceTemperature;
    }

    void VideoCapture::setAutoWhiteBalanceTemperature(bool autoWhiteBalanceTemperature) {
        [impl->wrapped setAutoWhiteBalanceTemperature:autoWhiteBalanceTemperature];
    }

    bool VideoCapture::getDefaultAutoWhiteBalanceTemperature() {
        return impl->wrapped.defaultAutoWhiteBalanceTemperature;
    }

    void VideoCapture::resetAutoWhiteBalanceTemperature() {
        [impl->wrapped resetAutoWhiteBalanceTemperature];
    }

    bool VideoCapture::isLEDOn() {
        return impl->wrapped.isLEDOn;
    }

    void VideoCapture::turnOnLED() {
        [impl->wrapped turnOnLED];
    }

    void VideoCapture::turnOffLED() {
        [impl->wrapped turnOffLED];
    }

    void VideoCapture::toggleLED() {
        [impl->wrapped toggleLED];
    }

    StereoDimensions VideoCapture::open(ColorSpace colorSpace) {
        return open(HD2K, FPS_15, colorSpace);
    }

    StereoDimensions VideoCapture::open(Resolution resolution, FrameRate frameRate, ColorSpace colorSpace) {
        StereoDimensions stereoDimensions = StereoDimensions(resolution);

        bool result = [impl->wrapped openWithResolution:resolution frameRate:frameRate colorSpace:colorSpace];

        if (!result) {
            throw std::runtime_error("Failed to open ZEDVideoCapture stream");
        }

        return stereoDimensions;
    }

    void VideoCapture::close() {
        [impl->wrapped close];
    }

    void VideoCapture::start(function<void(uint8_t*, size_t, size_t, size_t)> frameProcessor) {
        void (^frameProcessingBlock)(uint8_t*, size_t, size_t, size_t) = ^(uint8_t* data, size_t height, size_t width, size_t channels) {
            frameProcessor(data, height, width, channels);
        };

        [impl->wrapped start:frameProcessingBlock];
    }

    void VideoCapture::stop() {
        [impl->wrapped stop];
    }

    CalibrationData VideoCapture::getCalibrationData() {
        string serialNumber = getDeviceSerialNumber();

        CalibrationData calibrationData;
        calibrationData.load(serialNumber);

        return calibrationData;
    }
}

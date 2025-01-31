//
// camera_controls.cpp
// zed-open-capture-mac
//
// Created by Christian Bator on 01/28/2025
//

#include "zed_video_capture.h"
#include <opencv2/opencv.hpp>

using namespace std;
using namespace zed;

int main(int argc, const char* argv[]) {
    string windowName = "ZED";
    cv::namedWindow(windowName);

    VideoCapture videoCapture;
    StereoDimensions stereoDimensions = videoCapture.open(BGR);
    
    //
    // Camera properties
    //
    cout << "Device ID: " << videoCapture.getDeviceID() << endl;
    cout << "Device Name: " << videoCapture.getDeviceName() << endl;
    cout << "Device Serial Number: " << videoCapture.getDeviceSerialNumber() << endl;

    //
    // Camera control values
    //
    videoCapture.setBrightness(8);
    cout << "Brightness: " << videoCapture.getBrightness() << endl;

    videoCapture.setContrast(7);
    cout << "Contrast: " << videoCapture.getContrast() << endl;

    videoCapture.setHue(6);
    cout << "Hue: " << videoCapture.getHue() << endl;

    videoCapture.setSaturation(5);
    cout << "Saturation: " << videoCapture.getSaturation() << endl;

    videoCapture.setSharpness(4);
    cout << "Sharpness: " << videoCapture.getSharpness() << endl;

    videoCapture.setAutoWhiteBalanceTemperature(false);
    cout << "Auto white balance temperature: " << boolalpha << videoCapture.getAutoWhiteBalanceTemperature() << endl;

    videoCapture.setWhiteBalanceTemperature(5500);
    cout << "White balance temperature: " << videoCapture.getWhiteBalanceTemperature() << endl;

    //
    // Stream frames
    //
    cv::Mat bgrFrame(stereoDimensions.height, stereoDimensions.width, CV_8UC3);

    videoCapture.start([&bgrFrame, windowName](uint8_t* data, size_t height, size_t width, size_t channels) {
        memcpy(bgrFrame.data, data, height * width * channels);
        cv::imshow("ZED", bgrFrame);
    });

    while (true) {
        int key = cv::waitKey(1);

        if (key == 27) {
            break;
        }
        else if (key == 'j') {
            videoCapture.toggleLED();
        }
    }

    videoCapture.stop();
    videoCapture.close();

    return 0;
}

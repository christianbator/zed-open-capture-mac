//
// zed_video_capture.h
// zed-open-capture-mac
//
// Created by Christian Bator on 01/11/2025
//

#ifndef ZEDVIDEOCAPTURE_H
#define ZEDVIDEOCAPTURE_H

#include "zed_video_capture_format.h"
#include <functional>

using namespace std;

namespace zed {

    struct VideoCaptureImpl;

    class VideoCapture {

    private:
        VideoCaptureImpl* impl;
        StereoDimensions open(Resolution resolution, FrameRate frameRate, ColorSpace colorSpace);

    public:
        VideoCapture();
        ~VideoCapture();

        string getDeviceID();
        string getDeviceName();

        uint16_t getBrightness();
        void setBrightness(uint16_t brightness);
        uint16_t getDefaultBrightness();
        void resetBrightness();

        uint16_t getContrast();
        void setContrast(uint16_t contrast);
        uint16_t getDefaultContrast();
        void resetContrast();

        uint16_t getHue();
        void setHue(uint16_t hue);
        uint16_t getDefaultHue();
        void resetHue();

        uint16_t getSaturation();
        void setSaturation(uint16_t saturation);
        uint16_t getDefaultSaturation();
        void resetSaturation();

        uint16_t getSharpness();
        void setSharpness(uint16_t sharpness);
        uint16_t getDefaultSharpness();
        void resetSharpness();

        uint16_t getWhiteBalanceTemperature();
        void setWhiteBalanceTemperature(uint16_t whiteBalanceTemperature);
        uint16_t getDefaultWhiteBalanceTemperature();
        void resetWhiteBalanceTemperature();

        bool getAutoWhiteBalanceTemperature();
        void setAutoWhiteBalanceTemperature(bool autoWhiteBalanceTemperature);
        bool getDefaultAutoWhiteBalanceTemperature();
        void resetAutoWhiteBalanceTemperature();

        StereoDimensions open(ColorSpace colorSpace);

        template <Resolution resolution, FrameRate frameRate> StereoDimensions open(ColorSpace colorSpace) {
            // Verify frame rate for resolution at compile-time
            if constexpr (resolution == HD2K) {
                static_assert(frameRate == FPS_15, "Invalid frame rate for HD2K resolution, available frame rates: FPS_15");
            }
            else if constexpr (resolution == HD1080) {
                static_assert(frameRate == FPS_15 || frameRate == FPS_30, "Invalid frame rate for HD1080 resolution, available frame rates: FPS_15, FPS_30");
            }
            else if constexpr (resolution == HD720) {
                static_assert(frameRate == FPS_15 || frameRate == FPS_30 || frameRate == FPS_60,
                    "Invalid frame rate for HD720 resolution, available frame rates: FPS_15, FPS_30, FPS_60");
            }
            else if constexpr (resolution == VGA) {
                static_assert(frameRate == FPS_15 || frameRate == FPS_30 || frameRate == FPS_60 || frameRate == FPS_100,
                    "Invalid frame rate for VGA resolution, available frame rates: FPS_15, FPS_30, FPS_60, FPS_100");
            }
            else {
                static_assert(false, "Unsupported resolution");
            }

            return open(resolution, frameRate, colorSpace);
        }

        void close();

        void start(function<void(uint8_t*, size_t, size_t, size_t)> frameProcessor);
        void stop();
    };

}

#endif

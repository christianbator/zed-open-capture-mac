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

//
// zed_video_capture.h
// zed-open-capture-mac
//
// Created by Christian Bator on 01/11/2025
//

#ifndef ZEDVIDEOCAPTURE_HPP
#define ZEDVIDEOCAPTURE_HPP

#include <functional>

using namespace std;

namespace zed {

    enum VideoCaptureFormat {
        BGRA = 0,
        YUV = 1
    };

    struct VideoCaptureImpl;

    class VideoCapture {
        VideoCaptureImpl *impl;

      public:
        VideoCapture(VideoCaptureFormat);
        ~VideoCapture();

        void start(function<void(uint8_t *, size_t, size_t, size_t)> frameProcessor);
        void stop();
    };

} // namespace zed

#endif

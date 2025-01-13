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

    enum VideoCaptureFormat { YUV = 0, GREYSCALE = 1, RGB = 2 };

    struct VideoCaptureImpl;

    class VideoCapture {
        VideoCaptureImpl *impl;

      public:
        VideoCapture();
        ~VideoCapture();

        void open(VideoCaptureFormat videoCaptureFormat);
        void close();

        void start(function<void(uint8_t *, size_t, size_t, size_t)> frameProcessor);
        void stop();
    };

} // namespace zed

#endif

//
// zed_brainwave_plugin.cpp
// brainwave
//
// Created by Christian Bator on 02/02/2025
//

#include <cassert>
#include "../include/zed_video_capture.h"

using namespace std;
using namespace zed;

static VideoCapture *videoCapture = nullptr;

void reset() {
    delete videoCapture;
    videoCapture = nullptr;
}

extern "C" {
    __attribute__((visibility("default")))
    void open(ColorSpace colorSpace, StereoDimensions* stereoDimensions) {
        assert(videoCapture == nullptr);

        videoCapture = new VideoCapture();
        *stereoDimensions = videoCapture->open<HD720, FPS_60>(colorSpace);
    }

    __attribute__((visibility("default")))
    void start(uint8_t* frameBuffer, int* isNextFrameAvailable) {
        assert(videoCapture != nullptr);
        
        videoCapture->start([frameBuffer, isNextFrameAvailable](uint8_t* data, size_t height, size_t width, size_t channels) {
            memcpy(frameBuffer, data, height * width * channels);
            *isNextFrameAvailable = 1;
        });
    }

    __attribute__((visibility("default")))
    void stop() {
        assert(videoCapture != nullptr);

        videoCapture->stop();
    }

    __attribute__((visibility("default")))
    void close() {
        assert(videoCapture != nullptr);

        videoCapture->close();
        reset();
    }
}

//
// zed_video_capture.mm
// zed-open-capture-mac
//
// Created by Christian Bator on 01/11/2025
//

#include "../include/zed_video_capture.hpp"
#import "ZEDVideoCapture.h"

using namespace std;
using namespace zed;

namespace zed {

    struct VideoCaptureImpl {
        ZEDVideoCapture *wrapped;
    };

    VideoCapture::VideoCapture(VideoCaptureFormat videoCaptureFormat)
    {
        impl = new VideoCaptureImpl();
        impl->wrapped = [[ZEDVideoCapture alloc] initWithVideoCaptureFormat:videoCaptureFormat];

        if (!impl->wrapped) {
            throw std::runtime_error("Failed to create ZEDVideoCapture object");
        }
    }

    VideoCapture::~VideoCapture()
    {
        if (impl) {
            delete impl;
        }
    }

    void VideoCapture::start(function<void(uint8_t *, size_t, size_t, size_t)> frameProcessor)
    {
        void (^frameProcessingBlock)(uint8_t *, size_t, size_t, size_t) = ^(uint8_t *data, size_t height, size_t width, size_t channels) {
          frameProcessor(data, height, width, channels);
        };

        [impl->wrapped start:frameProcessingBlock];
    }

    void VideoCapture::stop() { [impl->wrapped stop]; }
} // namespace zed

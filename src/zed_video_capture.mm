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
        ZEDVideoCapture *wrapped;

        VideoCaptureImpl() { wrapped = [[ZEDVideoCapture alloc] init]; };
    };

    VideoCapture::VideoCapture() { impl = new VideoCaptureImpl(); }

    VideoCapture::~VideoCapture()
    {
        if (impl) {
            delete impl;
        }
    }

    StereoDimensions VideoCapture::open(ColorSpace colorSpace) { return open(HD2K, FPS_15, colorSpace); }

    StereoDimensions VideoCapture::open(Resolution resolution, FrameRate frameRate, ColorSpace colorSpace)
    {   
        StereoDimensions stereoDimensions = StereoDimensions(resolution);

        bool result = [impl->wrapped openWithStereoDimensions:stereoDimensions frameRate:frameRate colorSpace:colorSpace];

        if (!result) {
            throw std::runtime_error("Failed to open ZEDVideoCapture stream");
        }

        return stereoDimensions;
    }

    void VideoCapture::close() { [impl->wrapped close]; }

    void VideoCapture::start(function<void(uint8_t *, size_t, size_t, size_t)> frameProcessor)
    {
        void (^frameProcessingBlock)(uint8_t *, size_t, size_t, size_t) = ^(uint8_t *data, size_t height, size_t width, size_t channels) {
          frameProcessor(data, height, width, channels);
        };

        [impl->wrapped start:frameProcessingBlock];
    }

    void VideoCapture::stop() { [impl->wrapped stop]; }
} // namespace zed

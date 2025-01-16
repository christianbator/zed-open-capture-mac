//
// zed_video_capture_format.h
// zed-open-capture-mac
//
// Created by Christian Bator on 01/15/2025
//

#ifndef ZED_VIDEO_CAPTURE_FORMAT_H
#define ZED_VIDEO_CAPTURE_FORMAT_H

#include <format>

using namespace std;

namespace zed {

    enum Resolution {
        HD2K,   // 2208 x 1242, Available frame rates: 15 fps
        HD1080, // 1920 x 1080, Available frame rates: 15, 30 fps
        HD720,  // 1280 x 720,  Available frame rates: 15, 30, 60 fps
        VGA     // 672 x 376,   Available frame rates: 15, 30, 60, 100 fps
    };

    enum FrameRate {
        FPS_15 = 15,    // ~66 ms per frame
        FPS_30 = 30,    // ~33 ms per frame
        FPS_60 = 60,    // ~16 ms per frame
        FPS_100 = 100   //  10 ms per frame   
    };

    enum ColorSpace {
        YUV,        // YUV 4:2:2 in Y0, Cb, Y1, Cr order (8-bit) 
        GREYSCALE,  // 1 channel                         (8-bit)
        RGB,        // 3 channels                        (8-bit)
        BGR         // 3 channels                        (8-bit)
    };

    struct StereoDimensions {
        
        int width;
        int height;

        StereoDimensions(Resolution resolution) {
            switch (resolution) {
                case HD2K:
                    width = 2208 * 2;
                    height = 1242;
                    break;
                case HD1080:
                    width = 1920 * 2;
                    height = 1080;
                    break;
                case HD720:
                    width = 1280 * 2;
                    height = 720;
                    break;
                case VGA:
                    width = 672 * 2;
                    height = 376;
                    break;
            }
        }

        constexpr
        string toString() {
            return format("{}x{}", width, height);
        }
    };

    constexpr
    string resolutionToString(Resolution resolution) {
        switch (resolution) {
            case HD2K: return "HD2K";
            case HD1080: return "HD1080";
            case HD720: return "HD720";
            case VGA: return "VGA";
        }
    }

    constexpr
    string colorSpaceToString(ColorSpace colorSpace) {
        switch (colorSpace) {
            case YUV: return "YUV";
            case GREYSCALE: return "Greyscale";
            case RGB: return "RGB";
            case BGR: return "BGR";
        }
    }
}

#endif

//
// ZEDVideoCapture.h
// zed-open-capture-mac
//
// Created by Christian Bator on 01/11/2025
//

#include "../include/zed_video_capture_format.h"
#include <Foundation/Foundation.h>

struct Format;

@interface ZEDVideoCapture : NSObject

- (_Nonnull instancetype)init;

- (BOOL)openWithResolution:(zed::Resolution)resolution frameRate:(zed::FrameRate)frameRate colorSpace:(zed::ColorSpace)colorSpace;
- (void)close;

- (void)start:(void (^_Nonnull)(uint8_t* _Nonnull, size_t, size_t, size_t))frameProcessingBlock;
- (void)stop;

@end

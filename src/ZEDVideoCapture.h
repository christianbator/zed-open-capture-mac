//
// ZEDVideoCapture.h
// zed-open-capture-mac
//
// Created by Christian Bator on 01/11/2025
//

#include <Foundation/Foundation.h>
#include "../include/zed_video_capture_format.h"

struct Format;

@interface ZEDVideoCapture : NSObject

- (BOOL)openWithStereoDimensions:(zed::StereoDimensions)stereoDimensions frameRate:(zed::FrameRate)frameRate colorSpace:(zed::ColorSpace)colorSpace;
- (void)close;

- (void)start:(void (^_Nonnull)(uint8_t *_Nonnull, size_t, size_t, size_t))frameProcessingBlock;
- (void)stop;

@end

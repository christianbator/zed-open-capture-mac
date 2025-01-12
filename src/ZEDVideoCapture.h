//
// ZEDVideoCapture.h
// zed-open-capture-mac
//
// Created by Christian Bator on 01/11/2025
//

#include <Foundation/Foundation.h>

@interface ZEDVideoCapture : NSObject

- (_Nullable instancetype)initWithVideoCaptureFormat:(int)videoCaptureFormat;

- (void)start:(void (^_Nonnull)(uint8_t *_Nonnull, size_t, size_t, size_t))frameProcessingBlock;
- (void)stop;

@end

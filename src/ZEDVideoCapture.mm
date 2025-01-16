//
// ZEDVideoCapture.m
// zed-open-capture-mac
//
// Created by Christian Bator on 01/11/2025
//

#import "ZEDVideoCapture.h"
#include <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>

@interface ZEDVideoCapture () <AVCaptureVideoDataOutputSampleBufferDelegate>

@property(nonatomic, assign) zed::FrameRate frameRate;
@property(nonatomic, assign) zed::ColorSpace colorSpace;

@property(nonatomic, strong, nullable) AVCaptureSession *session;
@property(nonatomic, strong, nullable) void (^frameProcessingBlock)(uint8_t *data, size_t height, size_t width, size_t channels);

@end

@implementation ZEDVideoCapture

vImage_Buffer sourceImageBuffer = {
    .data = nil
};

vImage_Buffer destinationImageBuffer = { 
    .data = nil
};

#pragma mark - Public Interface

- (BOOL)openWithStereoDimensions:(zed::StereoDimensions)stereoDimensions frameRate:(zed::FrameRate)frameRate colorSpace:(zed::ColorSpace)colorSpace
{
    //
    // Arguments
    //
    _frameRate = frameRate;
    _colorSpace = colorSpace;

    //
    // Session
    //
    _session = [[AVCaptureSession alloc] init];
    [_session beginConfiguration];

    //
    // Device
    //
    NSArray *devices = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[ AVCaptureDeviceTypeExternal ]
                                                                              mediaType:AVMediaTypeVideo
                                                                               position:AVCaptureDevicePositionUnspecified]
                           .devices;

    AVCaptureDevice *zedDevice = nil;
    for (AVCaptureDevice *device in devices) {
        NSString *deviceName = device.localizedName;
        if ([deviceName rangeOfString:@"ZED" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            zedDevice = device;
            break;
        }
    }

    if (!zedDevice) {
        NSLog(@"Failed to find a ZED device");
        return NO;
    }

    //
    // Format
    //
    AVCaptureDeviceFormat *desiredFormat = nil;
    CMTime desiredFrameDuration;

    for (AVCaptureDeviceFormat *format in zedDevice.formats) {
        if ([format.mediaType isEqualToString:AVMediaTypeVideo]) {
            CMFormatDescriptionRef formatDescription = format.formatDescription;
            CMVideoDimensions formatDimensions = CMVideoFormatDescriptionGetDimensions(formatDescription);

            if (formatDimensions.width == stereoDimensions.width && formatDimensions.height == stereoDimensions.height) {
                NSArray<AVFrameRateRange *> *frameRateRanges = format.videoSupportedFrameRateRanges;
                for (AVFrameRateRange *frameRateRange in frameRateRanges) {
                    if (int(frameRateRange.minFrameRate) == frameRate && int(frameRateRange.maxFrameRate) == frameRate) {
                        desiredFormat = format;
                        desiredFrameDuration = frameRateRange.minFrameDuration;
                        break;
                    }
                }

                break;
            }
        }
    }

    if (!desiredFormat) {
        NSLog(@"Failed to detect desired format");
        return NO;
    }

    //
    // Device Format Configuration
    //
    NSError *configurationError = nil;
    [zedDevice lockForConfiguration:&configurationError];

    if (configurationError) {
        NSLog(@"Failed to configure desired format");
        [zedDevice unlockForConfiguration];
        _session = nil;
        return NO;
    }

    zedDevice.activeFormat = desiredFormat;
    zedDevice.activeVideoMinFrameDuration = desiredFrameDuration;
    zedDevice.activeVideoMaxFrameDuration = desiredFrameDuration;

    [zedDevice unlockForConfiguration];

    //
    // Input
    //
    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:zedDevice error:&error];
    if (error) {
        NSLog(@"Failed to create capture device input: %@", error.localizedDescription);
        _session = nil;
        return NO;
    }

    if ([_session canAddInput:input]) {
        [_session addInput:input];
    }
    else {
        NSLog(@"Failed to add input to session");
        _session = nil;
        return NO;
    }

    //
    // Output
    //
    AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
    output.alwaysDiscardsLateVideoFrames = YES;
    [output setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
    // dispatch_queue_create("co.bator.zed-video-capture-mac.frame-processing-queue", DISPATCH_QUEUE_SERIAL)

    NSMutableDictionary *outputVideoSettings = @{
        (id)kCVPixelBufferWidthKey: @(stereoDimensions.width),
        (id)kCVPixelBufferHeightKey: @(stereoDimensions.height)
    }.mutableCopy;

    switch (colorSpace) {
    case zed::YUV:
        outputVideoSettings[(id)kCVPixelBufferPixelFormatTypeKey] = @(kCVPixelFormatType_422YpCbCr8_yuvs);
        break;
    case zed::GREYSCALE:
        outputVideoSettings[(id)kCVPixelBufferPixelFormatTypeKey] = @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange);
        break;
    case zed::RGB:
    case zed::BGR:
        sourceImageBuffer.height = stereoDimensions.height;
        sourceImageBuffer.width = stereoDimensions.width;
        sourceImageBuffer.rowBytes = stereoDimensions.width * 4;

        destinationImageBuffer.height = stereoDimensions.height;
        destinationImageBuffer.width = stereoDimensions.width;
        destinationImageBuffer.rowBytes = stereoDimensions.width * 3;
        destinationImageBuffer.data = malloc(stereoDimensions.height * stereoDimensions.width * 3);

        outputVideoSettings[(id)kCVPixelBufferPixelFormatTypeKey] = colorSpace == zed::RGB ? @(kCVPixelFormatType_32ARGB) : @(kCVPixelFormatType_32BGRA);        
        break;
    }

    output.videoSettings = outputVideoSettings;

    if ([_session canAddOutput:output]) {
        [_session addOutput:output];
    }
    else {
        NSLog(@"Failed to add output to session");
        _session = nil;
        return NO;
    }

    //
    // Commit
    //
    [_session commitConfiguration];

    NSLog(@"Stream opened for %@ (stereo dimensions: %s, frame rate: %dfps, color space: %s)", zedDevice.localizedName,
          stereoDimensions.toString().c_str(), frameRate, zed::colorSpaceToString(colorSpace).c_str());
    
    return YES;
}

- (void)close
{
    [self stop];
    _session = nil;
}

- (void)start:(void (^)(uint8_t *, size_t, size_t, size_t))frameProcessingBlock
{
    if (!_session) {
        @throw [NSException exceptionWithName:@"ZEDVideoCaptureRuntimeError"
                                       reason:@"Attempted to start an unopened ZEDVideoCapture, call `open()` before `start()`"
                                     userInfo:nil];
    }

    _frameProcessingBlock = [frameProcessingBlock copy];

    [_session startRunning];
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    if (_frameProcessingBlock) {
        CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);

        CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);

        size_t height = CVPixelBufferGetHeight(pixelBuffer);
        size_t width = CVPixelBufferGetWidth(pixelBuffer);
        
        if (_colorSpace == zed::YUV) {
            uint8_t *yuvData = (uint8_t *)CVPixelBufferGetBaseAddress(pixelBuffer);
            _frameProcessingBlock(yuvData, height, width, 2);
        }
        else if (_colorSpace == zed::GREYSCALE) {
            uint8_t *greyscaleData = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
            _frameProcessingBlock(greyscaleData, height, width, 1);
        }
        else if (_colorSpace == zed::RGB) {
            sourceImageBuffer.data = (uint8_t *)CVPixelBufferGetBaseAddress(pixelBuffer);

            vImage_Error conversionError = vImageConvert_ARGB8888toRGB888(&sourceImageBuffer, &destinationImageBuffer, kvImageNoFlags);
            
            if (conversionError < 0) {
                @throw [NSException exceptionWithName:@"ZEDVideoCaptureRuntimeError"
                                       reason:@"Failed to convert video frame to RGB color space"
                                     userInfo:nil];
            }

            uint8_t *rgbData = (uint8_t *)destinationImageBuffer.data;
            _frameProcessingBlock(rgbData, height, width, 3);
        }
        else if (_colorSpace == zed::BGR) {
            sourceImageBuffer.data = (uint8_t *)CVPixelBufferGetBaseAddress(pixelBuffer);

            vImage_Error conversionError = vImageConvert_BGRA8888toBGR888(&sourceImageBuffer, &destinationImageBuffer, kvImageNoFlags);
            
            if (conversionError < 0) {
                @throw [NSException exceptionWithName:@"ZEDVideoCaptureRuntimeError"
                                       reason:@"Failed to convert video frame to BGR color space"
                                     userInfo:nil];
            }

            uint8_t *bgrData = (uint8_t *)destinationImageBuffer.data;
            _frameProcessingBlock(bgrData, height, width, 3);
        }

        CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    }
}

- (void)stop
{
    if (_session) {
        [_session stopRunning];
    }

    if (destinationImageBuffer.data) {
        free(destinationImageBuffer.data);
        destinationImageBuffer.data = nil;
    }

    _frameProcessingBlock = nil;
}

#pragma mark - Private

- (void)dealloc {
    if (destinationImageBuffer.data) {
        free(destinationImageBuffer.data);
        destinationImageBuffer.data = nil;
    }

    [super dealloc];
}

#pragma mark - Utilities

- (void)logAvailableOutputFormats:(AVCaptureVideoDataOutput *)output
{
    NSDictionary *formats = self.formats;
    NSMutableArray *formatDescriptions = [NSMutableArray array];

    for (NSNumber *format in [output availableVideoCVPixelFormatTypes]) {
        [formatDescriptions addObject:[formats objectForKey:format]];
    }

    NSLog(@"Available output formats: %@", formatDescriptions);
}

- (NSDictionary *_Nonnull)formats
{
    return [NSDictionary
        dictionaryWithObjectsAndKeys:@"kCVPixelFormatType_1Monochrome", [NSNumber numberWithInt:kCVPixelFormatType_1Monochrome], @"kCVPixelFormatType_2Indexed",
                                     [NSNumber numberWithInt:kCVPixelFormatType_2Indexed], @"kCVPixelFormatType_4Indexed",
                                     [NSNumber numberWithInt:kCVPixelFormatType_4Indexed], @"kCVPixelFormatType_8Indexed",
                                     [NSNumber numberWithInt:kCVPixelFormatType_8Indexed], @"kCVPixelFormatType_1IndexedGray_WhiteIsZero",
                                     [NSNumber numberWithInt:kCVPixelFormatType_1IndexedGray_WhiteIsZero], @"kCVPixelFormatType_2IndexedGray_WhiteIsZero",
                                     [NSNumber numberWithInt:kCVPixelFormatType_2IndexedGray_WhiteIsZero], @"kCVPixelFormatType_4IndexedGray_WhiteIsZero",
                                     [NSNumber numberWithInt:kCVPixelFormatType_4IndexedGray_WhiteIsZero], @"kCVPixelFormatType_8IndexedGray_WhiteIsZero",
                                     [NSNumber numberWithInt:kCVPixelFormatType_8IndexedGray_WhiteIsZero], @"kCVPixelFormatType_16BE555",
                                     [NSNumber numberWithInt:kCVPixelFormatType_16BE555], @"kCVPixelFormatType_16LE555",
                                     [NSNumber numberWithInt:kCVPixelFormatType_16LE555], @"kCVPixelFormatType_16LE5551",
                                     [NSNumber numberWithInt:kCVPixelFormatType_16LE5551], @"kCVPixelFormatType_16BE565",
                                     [NSNumber numberWithInt:kCVPixelFormatType_16BE565], @"kCVPixelFormatType_16LE565",
                                     [NSNumber numberWithInt:kCVPixelFormatType_16LE565], @"kCVPixelFormatType_24RGB",
                                     [NSNumber numberWithInt:kCVPixelFormatType_24RGB], @"kCVPixelFormatType_24BGR",
                                     [NSNumber numberWithInt:kCVPixelFormatType_24BGR], @"kCVPixelFormatType_32ARGB",
                                     [NSNumber numberWithInt:kCVPixelFormatType_32ARGB], @"kCVPixelFormatType_32BGRA",
                                     [NSNumber numberWithInt:kCVPixelFormatType_32BGRA], @"kCVPixelFormatType_32ABGR",
                                     [NSNumber numberWithInt:kCVPixelFormatType_32ABGR], @"kCVPixelFormatType_32RGBA",
                                     [NSNumber numberWithInt:kCVPixelFormatType_32RGBA], @"kCVPixelFormatType_64ARGB",
                                     [NSNumber numberWithInt:kCVPixelFormatType_64ARGB], @"kCVPixelFormatType_48RGB",
                                     [NSNumber numberWithInt:kCVPixelFormatType_48RGB], @"kCVPixelFormatType_32AlphaGray",
                                     [NSNumber numberWithInt:kCVPixelFormatType_32AlphaGray], @"kCVPixelFormatType_16Gray",
                                     [NSNumber numberWithInt:kCVPixelFormatType_16Gray], @"kCVPixelFormatType_422YpCbCr8",
                                     [NSNumber numberWithInt:kCVPixelFormatType_422YpCbCr8], @"kCVPixelFormatType_4444YpCbCrA8",
                                     [NSNumber numberWithInt:kCVPixelFormatType_4444YpCbCrA8], @"kCVPixelFormatType_4444YpCbCrA8R",
                                     [NSNumber numberWithInt:kCVPixelFormatType_4444YpCbCrA8R], @"kCVPixelFormatType_444YpCbCr8",
                                     [NSNumber numberWithInt:kCVPixelFormatType_444YpCbCr8], @"kCVPixelFormatType_422YpCbCr16",
                                     [NSNumber numberWithInt:kCVPixelFormatType_422YpCbCr16], @"kCVPixelFormatType_422YpCbCr10",
                                     [NSNumber numberWithInt:kCVPixelFormatType_422YpCbCr10], @"kCVPixelFormatType_444YpCbCr10",
                                     [NSNumber numberWithInt:kCVPixelFormatType_444YpCbCr10], @"kCVPixelFormatType_420YpCbCr8Planar",
                                     [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8Planar], @"kCVPixelFormatType_420YpCbCr8PlanarFullRange",
                                     [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8PlanarFullRange], @"kCVPixelFormatType_422YpCbCr_4A_8BiPlanar",
                                     [NSNumber numberWithInt:kCVPixelFormatType_422YpCbCr_4A_8BiPlanar], @"kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange",
                                     [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange],
                                     @"kCVPixelFormatType_420YpCbCr8BiPlanarFullRange", [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange],
                                     @"kCVPixelFormatType_422YpCbCr8_yuvs", [NSNumber numberWithInt:kCVPixelFormatType_422YpCbCr8_yuvs],
                                     @"kCVPixelFormatType_422YpCbCr8FullRange", [NSNumber numberWithInt:kCVPixelFormatType_422YpCbCr8FullRange], nil];
}

@end

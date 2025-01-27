//
// ZEDVideoCapture.m
// zed-open-capture-mac
//
// Created by Christian Bator on 01/11/2025
//

#import "ZEDVideoCapture.h"
#include "ZEDCamera.h"
#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#include <Foundation/Foundation.h>

@interface ZEDVideoCapture () <AVCaptureVideoDataOutputSampleBufferDelegate>

@property (nonatomic, assign) zed::Resolution resolution;
@property (nonatomic, assign) zed::StereoDimensions stereoDimensions;
@property (nonatomic, assign) zed::FrameRate frameRate;
@property (nonatomic, assign) zed::ColorSpace colorSpace;

@property (nonatomic, strong, nullable) AVCaptureSession* session;
@property (nonatomic, strong, nullable) AVCaptureDevice* device;
@property (nonatomic, strong, nullable) AVCaptureDeviceFormat* desiredFormat;
@property (nonatomic, assign) CMTime desiredFrameDuration;
@property (nonatomic, strong, nullable) void (^frameProcessingBlock)(uint8_t* data, size_t height, size_t width, size_t channels);

@property (nonatomic, strong) dispatch_queue_t queue;

@end

@implementation ZEDVideoCapture

vImage_Buffer sourceImageBuffer = {.data = nil};
vImage_Buffer destinationImageBuffer = {.data = nil};

#pragma mark - Public Interface

- (_Nonnull instancetype)init {
    [super init];

    _queue = dispatch_queue_create("co.bator.zed-video-capture-mac", DISPATCH_QUEUE_SERIAL);

    return self;
}

- (void)getAssociatedUVCInterface {
    ZEDCamera* camera = [ZEDCamera first];

    NSLog(@"Camera control values:\nbrightness = %u\nsharpness = %u\ncontrast = %u\nhue = %u\nsaturation = %u\ngamma = %u\ngain = %u\n",
        camera.brightness,
        camera.sharpness,
        camera.contrast,
        camera.hue,
        camera.saturation,
        camera.gamma,
        camera.gain);
}

- (BOOL)openWithResolution:(zed::Resolution)resolution frameRate:(zed::FrameRate)frameRate colorSpace:(zed::ColorSpace)colorSpace {
    //
    // Initialization
    //
    [self reset];

    [self getAssociatedUVCInterface];

    AVCaptureSession* session = [[AVCaptureSession alloc] init];
    [session beginConfiguration];

    zed::StereoDimensions stereoDimensions = zed::StereoDimensions(resolution);

    //
    // Device Discovery
    //
    AVCaptureDevice* device = nil;

    NSArray* zedDevices = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeExternal]
                                                                                 mediaType:AVMediaTypeVideo
                                                                                  position:AVCaptureDevicePositionUnspecified]
                              .devices;

    for (AVCaptureDevice* zedDevice in zedDevices) {
        NSString* deviceName = zedDevice.localizedName;
        if ([deviceName rangeOfString:@"ZED" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            device = zedDevice;
            break;
        }
    }

    if (!device) {
        NSLog(@"Failed to find a ZED device");
        return NO;
    }

    //
    // Format Detection
    //
    AVCaptureDeviceFormat* desiredFormat = nil;
    CMTime desiredFrameDuration = kCMTimeInvalid;

    for (AVCaptureDeviceFormat* format in device.formats) {
        if ([format.mediaType isEqualToString:AVMediaTypeVideo]) {
            CMFormatDescriptionRef formatDescription = format.formatDescription;
            CMVideoDimensions formatDimensions = CMVideoFormatDescriptionGetDimensions(formatDescription);

            if (formatDimensions.width == stereoDimensions.width && formatDimensions.height == stereoDimensions.height) {
                NSArray<AVFrameRateRange*>* frameRateRanges = format.videoSupportedFrameRateRanges;
                for (AVFrameRateRange* frameRateRange in frameRateRanges) {
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

    if (!desiredFormat || (CMTimeCompare(desiredFrameDuration, kCMTimeInvalid) == 0)) {
        NSLog(@"Failed to detect desired format");
        return NO;
    }

    //
    // Input Initialization
    //
    NSError* inputError = nil;
    AVCaptureDeviceInput* input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&inputError];
    if (inputError) {
        NSLog(@"Failed to create capture device input: %@", inputError.localizedDescription);
        return NO;
    }

    if ([session canAddInput:input]) {
        [session addInput:input];
    }
    else {
        NSLog(@"Failed to add input to session");
        return NO;
    }

    //
    // Output Initialization
    //
    AVCaptureVideoDataOutput* output = [[AVCaptureVideoDataOutput alloc] init];

    if ([session canAddOutput:output]) {
        [session addOutput:output];
    }
    else {
        NSLog(@"Failed to add output to session");
        return NO;
    }

    NSMutableDictionary* outputVideoSettings =
        @{(id)kCVPixelBufferWidthKey: @(stereoDimensions.width), (id)kCVPixelBufferHeightKey: @(stereoDimensions.height)}.mutableCopy;

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
    [output setSampleBufferDelegate:self queue:_queue];

    //
    // Finalization
    //
    [session commitConfiguration];

    _resolution = resolution;
    _stereoDimensions = stereoDimensions;
    _frameRate = frameRate;
    _colorSpace = colorSpace;

    _session = session;
    _device = device;
    _desiredFormat = desiredFormat;
    _desiredFrameDuration = desiredFrameDuration;

    NSLog(@"Stream opened for %@ (stereo dimensions: %s, frame rate: %d fps, "
          @"color space: %s)",
        _device.localizedName,
        _stereoDimensions.toString().c_str(),
        _frameRate,
        zed::colorSpaceToString(_colorSpace).c_str());

    return YES;
}

- (void)close {
    [self stop];
    [self reset];
}

- (void)start:(void (^)(uint8_t*, size_t, size_t, size_t))frameProcessingBlock {
    if (!_session) {
        @throw [NSException exceptionWithName:@"ZEDVideoCaptureRuntimeError"
                                       reason:@"Attempted to start an unopened ZEDVideoCapture, "
                                              @"call `open()` before `start()`"
                                     userInfo:nil];
    }

    _frameProcessingBlock = [frameProcessingBlock copy];

    [_session startRunning];

    NSAssert(_device != nil, @"Unexpectedly found nil device in `start()`");

    [_device lockForConfiguration:nil];
    _device.activeFormat = _desiredFormat;
    _device.activeVideoMinFrameDuration = _desiredFrameDuration;
    _device.activeVideoMaxFrameDuration = _desiredFrameDuration;
    [_device unlockForConfiguration];
}

- (void)captureOutput:(AVCaptureOutput*)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection*)connection {
    if (!_frameProcessingBlock) {
        return;
    }

    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);

    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);

    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    size_t width = CVPixelBufferGetWidth(pixelBuffer);

    if (_colorSpace == zed::YUV) {
        uint8_t* yuvData = (uint8_t*)CVPixelBufferGetBaseAddress(pixelBuffer);

        dispatch_async(dispatch_get_main_queue(), ^{
            _frameProcessingBlock(yuvData, height, width, 2);
        });
    }
    else if (_colorSpace == zed::GREYSCALE) {
        uint8_t* greyscaleData = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);

        dispatch_async(dispatch_get_main_queue(), ^{
            _frameProcessingBlock(greyscaleData, height, width, 1);
        });
    }
    else if (_colorSpace == zed::RGB) {
        sourceImageBuffer.data = (uint8_t*)CVPixelBufferGetBaseAddress(pixelBuffer);

        vImage_Error conversionError = vImageConvert_ARGB8888toRGB888(&sourceImageBuffer, &destinationImageBuffer, kvImageNoFlags);

        if (conversionError < 0) {
            @throw [NSException exceptionWithName:@"ZEDVideoCaptureRuntimeError" reason:@"Failed to convert video frame to RGB color space" userInfo:nil];
        }

        uint8_t* rgbData = (uint8_t*)destinationImageBuffer.data;

        dispatch_async(dispatch_get_main_queue(), ^{
            _frameProcessingBlock(rgbData, height, width, 3);
        });
    }
    else if (_colorSpace == zed::BGR) {
        sourceImageBuffer.data = (uint8_t*)CVPixelBufferGetBaseAddress(pixelBuffer);

        vImage_Error conversionError = vImageConvert_BGRA8888toBGR888(&sourceImageBuffer, &destinationImageBuffer, kvImageNoFlags);

        if (conversionError < 0) {
            @throw [NSException exceptionWithName:@"ZEDVideoCaptureRuntimeError" reason:@"Failed to convert video frame to BGR color space" userInfo:nil];
        }

        uint8_t* bgrData = (uint8_t*)destinationImageBuffer.data;

        dispatch_async(dispatch_get_main_queue(), ^{
            _frameProcessingBlock(bgrData, height, width, 3);
        });
    }

    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
}

- (void)stop {
    if (_session) {
        [_session stopRunning];
    }

    _frameProcessingBlock = nil;

    if (destinationImageBuffer.data) {
        free(destinationImageBuffer.data);
        destinationImageBuffer.data = nil;
    }
}

#pragma mark - Private

- (void)reset {
    _frameProcessingBlock = nil;
    _desiredFrameDuration = kCMTimeInvalid;
    _desiredFormat = nil;
    _device = nil;
    _session = nil;

    if (destinationImageBuffer.data) {
        free(destinationImageBuffer.data);
        destinationImageBuffer.data = nil;
    }
}

- (void)dealloc {
    [self reset];
    [super dealloc];
}

#pragma mark - Utilities

- (void)logCMTime:(CMTime)time {
    int value = time.value;
    int timescale = time.timescale;

    int frameRate = floor(float(timescale) / float(value));
    int frameDuration = floor(1.0 / float(frameRate) * 1000.0);

    NSLog(@"FPS: %d (%d ms)", frameRate, frameDuration);
}

@end

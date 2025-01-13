//
// ZEDVideoCapture.m
// zed-open-capture-mac
//
// Created by Christian Bator on 01/11/2025
//

#import "ZEDVideoCapture.h"
#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>

@interface ZEDVideoCapture () <AVCaptureVideoDataOutputSampleBufferDelegate>

@property(nonatomic, assign) int videoCaptureFormat;
@property(nonatomic, strong, nullable) AVCaptureSession *session;
@property(nonatomic, strong, nullable) void (^frameProcessingBlock)(uint8_t *data, size_t height, size_t width, size_t channels);

@end

@implementation ZEDVideoCapture

#pragma mark - Public Interface

- (BOOL)openWithVideoCaptureFormat:(int)videoCaptureFormat
{
    _videoCaptureFormat = videoCaptureFormat;
    _session = [[AVCaptureSession alloc] init];

    // Find the first available ZED video capture device
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

    // Create input from the device
    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:zedDevice error:&error];
    if (error) {
        NSLog(@"Failed to create capture device input: %@", error.localizedDescription);
        return NO;
    }

    // Add the input to the capture session
    if ([_session canAddInput:input]) {
        [_session addInput:input];
    }
    else {
        NSLog(@"Failed to add input to session");
        return NO;
    }

    // Create output to capture frames
    AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
    [output setAlwaysDiscardsLateVideoFrames:YES];
    [output setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
    // dispatch_queue_create("co.bator.zed-video-capture-mac.frame-processing-queue", DISPATCH_QUEUE_SERIAL)

    FourCharCode defaultDevicePixelFormat = CMFormatDescriptionGetMediaSubType(zedDevice.activeFormat.formatDescription);
    NSAssert(defaultDevicePixelFormat == kCVPixelFormatType_422YpCbCr8_yuvs, @"");

    switch (videoCaptureFormat) {
    // YUV
    case 0:;
        [output setVideoSettings:@{(id)kCVPixelBufferPixelFormatTypeKey : @(defaultDevicePixelFormat)}];
        break;

    // GREYSCALE
    case 1:;
        [output setVideoSettings:@{(id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)}];
        break;

    // RGB
    case 2:;
        [output setVideoSettings:@{(id)kCVPixelBufferPixelFormatTypeKey : @(defaultDevicePixelFormat)}];
        break;

    // Unimplemented
    default:
        NSLog(@"Unimplemented VideoCaptureFormat %d", _videoCaptureFormat);
        return NO;
    }

    // Add the output to the capture session
    if ([_session canAddOutput:output]) {
        [_session addOutput:output];
    }
    else {
        NSLog(@"Failed to add output to session");
        return NO;
    }

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
                                       reason:@"Attempted to start an unopened ZEDVideoCapture, call `open(VideoCaptureFormat)` before "
                                              @"`start(function<void(uint8_t *, size_t, size_t, size_t)> frameProcessor)`"
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
        uint8_t *data = (uint8_t *)CVPixelBufferGetBaseAddress(pixelBuffer);

        switch (_videoCaptureFormat) {
        // YUV
        case 0:;
            _frameProcessingBlock(data, height, width, 2);
            break;

        // GREYSCALE
        case 1:;
            uint8_t *greyscaleData = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
            _frameProcessingBlock(greyscaleData, height, width, 1);
            break;

        // RGB
        case 2:;
            vImageCVImageFormatRef sourceFormat = vImageCVImageFormat_CreateWithCVPixelBuffer(pixelBuffer);
            vImageCVImageFormat_SetChromaSiting(sourceFormat, kCVImageBufferChromaLocation_Center);

            vImage_CGImageFormat destinationFormat = {
                .bitsPerComponent = 8, .bitsPerPixel = 8 * 3, .colorSpace = CGColorSpaceCreateDeviceRGB(), .bitmapInfo = (CGBitmapInfo)kCGImageAlphaNone};

            vImage_Buffer rgbBuffer;
            vImageBuffer_InitWithCVPixelBuffer(&rgbBuffer, &destinationFormat, pixelBuffer, sourceFormat, nil, kvImageNoFlags);

            _frameProcessingBlock(rgbBuffer.data, height, width, 3);

            vImageCVImageFormat_Release(sourceFormat);
            free(rgbBuffer.data);
            break;

        // Unimplemented
        default:
            @throw [NSException exceptionWithName:@"ZEDVideoCaptureRuntimeError"
                                           reason:[NSString stringWithFormat:@"Unimplemented video capture format: %d", _videoCaptureFormat]
                                         userInfo:nil];
        }

        CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    }
}

- (void)stop
{
    [_session stopRunning];
    _frameProcessingBlock = nil;
}

#pragma mark - Private Methods

- (void)logDeviceFormat:(AVCaptureDevice *)device
{
    NSNumber *formatValue = [NSNumber numberWithInt:CMFormatDescriptionGetMediaSubType(device.activeFormat.formatDescription)];
    NSDictionary *formats = self.formats;

    NSLog(@"Device format: %@", formats[formatValue]);
}

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

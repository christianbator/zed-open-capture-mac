//
// ZEDVideoCapture.m
// zed-open-capture-mac
//
// Created by Christian Bator on 01/11/2025
//

#import "ZEDVideoCapture.h"
#import <AVFoundation/AVFoundation.h>

@interface ZEDVideoCapture () <AVCaptureVideoDataOutputSampleBufferDelegate>

@property (nonatomic, assign) OSType pixelFormat;
@property (nonatomic, assign) int channels;

@property(nonatomic, strong, nonnull) AVCaptureSession *session;
@property(nonatomic, strong, nullable) void (^frameProcessingBlock)(uint8_t *data, size_t height, size_t width, size_t channels);

@end

@implementation ZEDVideoCapture

- (_Nullable instancetype)initWithVideoCaptureFormat:(int)videoCaptureFormat
{
    self = [super init];

    if (self) {
        switch (videoCaptureFormat) {
            case 0:
                _pixelFormat = kCVPixelFormatType_32BGRA;
                _channels = 4;
                break;
            case 1:
                _pixelFormat = kCVPixelFormatType_422YpCbCr8_yuvs;
                _channels = 2;
                break;
            default:
                NSLog(@"Unimplemented VideoCaptureFormat %d", videoCaptureFormat);
                return nil;
        }

        // Create a capture session
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
            return nil;
        }

        // Create input from the device
        NSError *error = nil;
        AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:zedDevice error:&error];
        if (error) {
            NSLog(@"Failed to create capture device input: %@", error.localizedDescription);
            return nil;
        }

        // Add the input to the capture session
        if ([_session canAddInput:input]) {
            [_session addInput:input];
        }
        else {
            NSLog(@"Failed to add input to session");
            return nil;
        }

        // Create output to capture frames
        AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
        [output setVideoSettings:@{(id)kCVPixelBufferPixelFormatTypeKey: @(_pixelFormat)}];
        [output setAlwaysDiscardsLateVideoFrames:YES];
        [output setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
        // [output setSampleBufferDelegate:self queue:dispatch_queue_create("co.bator.zed-video-capture-mac.frame-processing-queue", DISPATCH_QUEUE_SERIAL)];

        // Add the output to the capture session
        if ([_session canAddOutput:output]) {
            [_session addOutput:output];
        }
        else {
            NSLog(@"Failed to add output to session");
            return nil;
        }
    }

    return self;
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    if (_frameProcessingBlock) {
        CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);

        CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);

        OSType pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
        NSAssert(pixelFormat == _pixelFormat, @"Unexpected pixel format");

        size_t height = CVPixelBufferGetHeight(pixelBuffer);
        size_t width = CVPixelBufferGetWidth(pixelBuffer);
        uint8_t *data = (uint8_t *)CVPixelBufferGetBaseAddress(pixelBuffer);
        
        _frameProcessingBlock(data, height, width, _channels);

        CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    }
}

- (void)start:(void (^)(uint8_t *, size_t, size_t, size_t))frameProcessingBlock
{
    _frameProcessingBlock = [frameProcessingBlock copy];
    [_session startRunning];
}

- (void)stop
{
    [_session stopRunning];
}

@end

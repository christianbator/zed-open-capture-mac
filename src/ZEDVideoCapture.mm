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
#import <Foundation/Foundation.h>
#import <IOKit/IOCFPlugIn.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/usb/IOUSBLib.h>

//
// UVC Request Codes
//
#define kUVCSetCurrent 0x01
#define kUVCGetCurrent 0x81

//
// ZED Interface
//
#define kZEDControlIndex 3
#define kZEDControlValueSizeInBytes 2

//
// ZED Control Codes
//
#define kZEDBrightness 2
#define kZEDContrast 3
#define kZEDHue 6
#define kZEDSaturation 7
#define kZEDSharpness 8
#define kZEDGamma 9
#define kZEDWhiteBalanceTemperature 10
#define kZEDAutoWhiteBalanceTemperature 11

//
// ZEDVideoCapture
//
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

@property (nonatomic, assign) IOUSBInterfaceInterface300** uvcInterface;

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

- (BOOL)openWithResolution:(zed::Resolution)resolution frameRate:(zed::FrameRate)frameRate colorSpace:(zed::ColorSpace)colorSpace {
    //
    // Initialization
    //
    [self reset];

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
    // Matching USB Interface Discovery
    //
    io_service_t usbDevice = [self findUSBDeviceWithID:device.uniqueID];

    if (!usbDevice) {
        return NO;
    }

    IOUSBInterfaceInterface300** uvcInterface = [self findUVCInterfaceForUSBDevice:usbDevice];
    IOObjectRelease(usbDevice);

    if (!uvcInterface) {
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

    _deviceID = device.uniqueID;
    _deviceName = device.localizedName;

    _resolution = resolution;
    _stereoDimensions = stereoDimensions;
    _frameRate = frameRate;
    _colorSpace = colorSpace;

    _session = session;
    _device = device;
    _desiredFormat = desiredFormat;
    _desiredFrameDuration = desiredFrameDuration;

    _uvcInterface = uvcInterface;

    NSLog(@"Stream opened for %@ (stereo dimensions: %s, frame rate: %d fps, "
          @"color space: %s)",
        _device.localizedName,
        _stereoDimensions.toString().c_str(),
        _frameRate,
        zed::colorSpaceToString(_colorSpace).c_str());

    return YES;
}

- (io_service_t)findUSBDeviceWithID:(NSString*)uniqueID {
    io_iterator_t usbDeviceIterator;
    kern_return_t usbQueryResult = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(kIOUSBDeviceClassName), &usbDeviceIterator);

    if (usbQueryResult != KERN_SUCCESS) {
        return 0;
    }
    else if (!usbDeviceIterator) {
        return 0;
    }

    io_service_t usbDevice = 0;

    while ((usbDevice = IOIteratorNext(usbDeviceIterator))) {
        uint32_t locationId = 0;
        uint16_t vendorId = 0;
        uint16_t productId = 0;

        CFTypeRef locationIdRef = IORegistryEntrySearchCFProperty(usbDevice, kIOUSBPlane, CFSTR(kUSBDevicePropertyLocationID), kCFAllocatorDefault, 0);
        CFTypeRef vendorIdRef = IORegistryEntrySearchCFProperty(usbDevice, kIOUSBPlane, CFSTR(kUSBVendorID), kCFAllocatorDefault, 0);
        CFTypeRef productIdRef = IORegistryEntrySearchCFProperty(usbDevice, kIOUSBPlane, CFSTR(kUSBProductID), kCFAllocatorDefault, 0);

        if (locationIdRef && CFGetTypeID(locationIdRef) == CFNumberGetTypeID()) {
            CFNumberGetValue((CFNumberRef)locationIdRef, kCFNumberSInt32Type, &locationId);
            CFRelease(locationIdRef);
        }

        if (vendorIdRef && CFGetTypeID(vendorIdRef) == CFNumberGetTypeID()) {
            CFNumberGetValue((CFNumberRef)vendorIdRef, kCFNumberSInt16Type, &vendorId);
            CFRelease(vendorIdRef);
        }

        if (productIdRef && CFGetTypeID(productIdRef) == CFNumberGetTypeID()) {
            CFNumberGetValue((CFNumberRef)productIdRef, kCFNumberSInt16Type, &productId);
            CFRelease(productIdRef);
        }

        NSString* usbDeviceID = [NSString stringWithFormat:@"0x%x%x%x", locationId, vendorId, productId];

        if ([usbDeviceID isEqualToString:uniqueID]) {
            break;
        }
        else {
            IOObjectRelease(usbDevice);
        }
    }

    IOObjectRelease(usbDeviceIterator);

    return usbDevice;
}

- (IOUSBInterfaceInterface300**)findUVCInterfaceForUSBDevice:(io_service_t)usbDevice {
    IOCFPlugInInterface** plugInInterface = NULL;
    SInt32 score;
    kern_return_t kernelResult = IOCreatePlugInInterfaceForService(usbDevice, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &plugInInterface, &score);

    if ((kernelResult != kIOReturnSuccess) || !plugInInterface) {
        return NULL;
    }

    IOUSBDeviceInterface** deviceInterface = NULL;
    IOReturn ioResult = (*plugInInterface)->QueryInterface(plugInInterface, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID), (LPVOID*)&deviceInterface);
    IODestroyPlugInInterface(plugInInterface);

    if ((ioResult != 0) || !deviceInterface) {
        return NULL;
    }

    io_iterator_t interfaceIterator;
    IOUSBFindInterfaceRequest interfaceRequest = {.bInterfaceClass = kUSBVideoInterfaceClass,
        .bInterfaceSubClass = kUSBVideoControlSubClass,
        .bInterfaceProtocol = kIOUSBFindInterfaceDontCare,
        .bAlternateSetting = kIOUSBFindInterfaceDontCare};

    ioResult = (*deviceInterface)->CreateInterfaceIterator(deviceInterface, &interfaceRequest, &interfaceIterator);
    (*deviceInterface)->Release(deviceInterface);

    if ((ioResult != 0) || !interfaceIterator) {
        return NULL;
    }

    io_service_t usbInterface = IOIteratorNext(interfaceIterator);
    IOObjectRelease(interfaceIterator);

    if (!usbInterface) {
        return NULL;
    }

    kernelResult = IOCreatePlugInInterfaceForService(usbInterface, kIOUSBInterfaceUserClientTypeID, kIOCFPlugInInterfaceID, &plugInInterface, &score);
    IOObjectRelease(usbInterface);

    if ((kernelResult != kIOReturnSuccess) || !plugInInterface) {
        return NULL;
    }

    IOUSBInterfaceInterface300** uvcInterface = NULL;
    ioResult = (*plugInInterface)->QueryInterface(plugInInterface, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID), (LPVOID*)&uvcInterface);
    IODestroyPlugInInterface(plugInInterface);

    if ((ioResult != 0) || !uvcInterface) {
        return NULL;
    }

    return uvcInterface;
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

- (UInt16)brightness {
    return [self getValueForCode:kZEDBrightness];
}

- (void)setBrightness:(UInt16)brightness {
    [self setValue:brightness forCode:kZEDBrightness];
}

- (UInt16)contrast {
    return [self getValueForCode:kZEDContrast];
}

- (void)setContrast:(UInt16)contrast {
    [self setValue:contrast forCode:kZEDContrast];
}

- (UInt16)hue {
    return [self getValueForCode:kZEDHue];
}

- (void)setHue:(UInt16)hue {
    [self setValue:hue forCode:kZEDHue];
}

- (UInt16)saturation {
    return [self getValueForCode:kZEDSaturation];
}

- (void)setSaturation:(UInt16)saturation {
    [self setValue:saturation forCode:kZEDSaturation];
}

- (UInt16)sharpness {
    return [self getValueForCode:kZEDSharpness];
}

- (void)setSharpness:(UInt16)sharpness {
    [self setValue:sharpness forCode:kZEDSharpness];
}

- (UInt16)whiteBalanceTemperature {
    return [self getValueForCode:kZEDWhiteBalanceTemperature];
}

- (void)setWhiteBalanceTemperature:(UInt16)whiteBalanceTemperature {
    self.autoWhiteBalanceTemperature = NO;
    [self setValue:whiteBalanceTemperature forCode:kZEDWhiteBalanceTemperature];
}

- (BOOL)autoWhiteBalanceTemperature {
    return [self getValueForCode:kZEDAutoWhiteBalanceTemperature];
}

- (void)setAutoWhiteBalanceTemperature:(BOOL)autoWhiteBalanceTemperature {
    [self setValue:autoWhiteBalanceTemperature forCode:kZEDAutoWhiteBalanceTemperature];
}

#pragma mark - Private

- (UInt16)getValueForCode:(UInt16)valueCode {
    IOReturn result = (*_uvcInterface)->USBInterfaceOpen(_uvcInterface);

    if (result != kIOReturnSuccess && result != kIOReturnExclusiveAccess) {
        @throw [NSException exceptionWithName:@"ZEDCameraRuntimeError" reason:@"Failed to open USB interface" userInfo:nil];
    }

    UInt16 data = 0;

    IOUSBDevRequest controlRequest = {.bmRequestType = USBmakebmRequestType((UInt8)kUSBIn, (UInt8)kUSBClass, (UInt8)kUSBInterface),
        .bRequest = kUVCGetCurrent,
        .wValue = UInt16(valueCode << 8),
        .wIndex = kZEDControlIndex << 8,
        .wLength = kZEDControlValueSizeInBytes,
        .pData = &data,
        .wLenDone = 0};

    result = (*_uvcInterface)->ControlRequest(_uvcInterface, 0, &controlRequest);

    if (result != kIOReturnSuccess) {
        @throw [NSException exceptionWithName:@"ZEDCameraRuntimeError" reason:@"Failed to send USB request" userInfo:nil];
    }

    (*_uvcInterface)->USBInterfaceClose(_uvcInterface);

    return data;
}

- (void)setValue:(UInt16)value forCode:(UInt16)valueCode {
    IOReturn result = (*_uvcInterface)->USBInterfaceOpen(_uvcInterface);

    if (result != kIOReturnSuccess && result != kIOReturnExclusiveAccess) {
        @throw [NSException exceptionWithName:@"ZEDCameraRuntimeError" reason:@"Failed to open USB interface" userInfo:nil];
    }

    IOUSBDevRequest controlRequest = {.bmRequestType = USBmakebmRequestType((UInt8)kUSBOut, (UInt8)kUSBClass, (UInt8)kUSBInterface),
        .bRequest = kUVCSetCurrent,
        .wValue = UInt16(valueCode << 8),
        .wIndex = kZEDControlIndex << 8,
        .wLength = kZEDControlValueSizeInBytes,
        .pData = &value,
        .wLenDone = 0};

    result = (*_uvcInterface)->ControlRequest(_uvcInterface, 0, &controlRequest);

    if (result != kIOReturnSuccess) {
        @throw [NSException exceptionWithName:@"ZEDCameraRuntimeError" reason:@"Failed to send USB request" userInfo:nil];
    }

    (*_uvcInterface)->USBInterfaceClose(_uvcInterface);
}

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

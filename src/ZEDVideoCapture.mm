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
// UVC Interface
//
#define kUVCUnitID 3
#define kUVCControlValueSizeInBytes 2

typedef NS_ENUM(UInt8, UVCRequestType) { UVCRequestTypeIn = 0xa1, UVCRequestTypeOut = 0x21 };
typedef NS_ENUM(UInt8, UVCRequest) { UVCRequestGetCurrent = 0x81, UVCRequestSetCurrent = 0x01 };

//
// UVC Control Codes
//
typedef NS_ENUM(UInt8, UVCControlCode) {
    UVCBrightness = 2,
    UVCContrast = 3,
    UVCHue = 6,
    UVCSaturation = 7,
    UVCSharpness = 8,
    UVCWhiteBalanceTemperature = 10,
    UVCAutoWhiteBalanceTemperature = 11
};

//
// ZED Extension Unit Interface
//
#define kXUID 4
#define kXUControlSelector 2
#define kXUBufferSizeInBytes 384

typedef NS_ENUM(UInt8, XURequestType) { XURequestTypeIn = 0xa0, XURequestTypeOut = 0x20 };
typedef NS_ENUM(UInt8, XURequest) { XUReadRequest, XUWriteRequest };
typedef NS_ENUM(UInt8, GPIONumber) { GPIONumberLED = 2 };
typedef NS_ENUM(UInt8, GPIODirection) { GPIODirectionOut = 0, GPIODirectionIn = 1 };

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

@property (nonatomic, assign) io_service_t usbDevice;
@property (nonatomic, assign) IOUSBInterfaceInterface300** uvcInterface;

@property (nonatomic, assign) vImage_Buffer sourceImageBuffer;
@property (nonatomic, assign) vImage_Buffer destinationImageBuffer;

@end

@implementation ZEDVideoCapture

#pragma mark - Public Interface

- (_Nonnull instancetype)init {
    [super init];

    _defaultBrightness = 4;
    _defaultContrast = 4;
    _defaultHue = 0;
    _defaultSaturation = 4;
    _defaultSharpness = 0;
    _defaultWhiteBalanceTemperature = 4600;
    _defaultAutoWhiteBalanceTemperature = YES;

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
        NSLog(@"Failed to find a USB device");
        return NO;
    }

    IOUSBInterfaceInterface300** uvcInterface = [self findUVCInterfaceForUSBDevice:usbDevice];

    if (!uvcInterface) {
        NSLog(@"Failed to find a UVC interface");
        IOObjectRelease(usbDevice);
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
            _sourceImageBuffer.height = stereoDimensions.height;
            _sourceImageBuffer.width = stereoDimensions.width;
            _sourceImageBuffer.rowBytes = stereoDimensions.width * 4;

            _destinationImageBuffer.height = stereoDimensions.height;
            _destinationImageBuffer.width = stereoDimensions.width;
            _destinationImageBuffer.rowBytes = stereoDimensions.width * 3;
            _destinationImageBuffer.data = malloc(stereoDimensions.height * stereoDimensions.width * 3);

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

    _usbDevice = usbDevice;
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

- (IOUSBInterfaceInterface300** _Nullable)findUVCInterfaceForUSBDevice:(io_service_t)usbDevice {
    IOCFPlugInInterface** plugInInterface = nil;
    SInt32 score;
    kern_return_t kernelResult = IOCreatePlugInInterfaceForService(usbDevice, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &plugInInterface, &score);

    if ((kernelResult != kIOReturnSuccess) || !plugInInterface) {
        return nil;
    }

    IOUSBDeviceInterface300** deviceInterface = nil;
    IOReturn ioResult = (*plugInInterface)->QueryInterface(plugInInterface, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID), (LPVOID*)&deviceInterface);
    IODestroyPlugInInterface(plugInInterface);

    if ((ioResult != 0) || !deviceInterface) {
        return nil;
    }

    io_iterator_t interfaceIterator;
    IOUSBFindInterfaceRequest interfaceRequest = {.bInterfaceClass = kUSBVideoInterfaceClass,
        .bInterfaceSubClass = kUSBVideoControlSubClass,
        .bInterfaceProtocol = kIOUSBFindInterfaceDontCare,
        .bAlternateSetting = kIOUSBFindInterfaceDontCare};

    ioResult = (*deviceInterface)->CreateInterfaceIterator(deviceInterface, &interfaceRequest, &interfaceIterator);
    (*deviceInterface)->Release(deviceInterface);

    if ((ioResult != 0) || !interfaceIterator) {
        return nil;
    }

    io_service_t usbInterface = IOIteratorNext(interfaceIterator);
    IOObjectRelease(interfaceIterator);

    if (!usbInterface) {
        return nil;
    }

    kernelResult = IOCreatePlugInInterfaceForService(usbInterface, kIOUSBInterfaceUserClientTypeID, kIOCFPlugInInterfaceID, &plugInInterface, &score);
    IOObjectRelease(usbInterface);

    if ((kernelResult != kIOReturnSuccess) || !plugInInterface) {
        return nil;
    }

    IOUSBInterfaceInterface300** uvcInterface = nil;
    ioResult = (*plugInInterface)->QueryInterface(plugInInterface, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID), (LPVOID*)&uvcInterface);
    IODestroyPlugInInterface(plugInInterface);

    if ((ioResult != 0) || !uvcInterface) {
        return nil;
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

    [self turnOnLED];
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
        _sourceImageBuffer.data = (uint8_t*)CVPixelBufferGetBaseAddress(pixelBuffer);

        vImage_Error conversionError = vImageConvert_ARGB8888toRGB888(&_sourceImageBuffer, &_destinationImageBuffer, kvImageNoFlags);

        if (conversionError < 0) {
            @throw [NSException exceptionWithName:@"ZEDVideoCaptureRuntimeError" reason:@"Failed to convert video frame to RGB color space" userInfo:nil];
        }

        uint8_t* rgbData = (uint8_t*)_destinationImageBuffer.data;

        dispatch_async(dispatch_get_main_queue(), ^{
            _frameProcessingBlock(rgbData, height, width, 3);
        });
    }
    else if (_colorSpace == zed::BGR) {
        _sourceImageBuffer.data = (uint8_t*)CVPixelBufferGetBaseAddress(pixelBuffer);

        vImage_Error conversionError = vImageConvert_BGRA8888toBGR888(&_sourceImageBuffer, &_destinationImageBuffer, kvImageNoFlags);

        if (conversionError < 0) {
            @throw [NSException exceptionWithName:@"ZEDVideoCaptureRuntimeError" reason:@"Failed to convert video frame to BGR color space" userInfo:nil];
        }

        uint8_t* bgrData = (uint8_t*)_destinationImageBuffer.data;

        dispatch_async(dispatch_get_main_queue(), ^{
            _frameProcessingBlock(bgrData, height, width, 3);
        });
    }

    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
}

- (void)stop {
    [self turnOffLED];

    if (_session) {
        [_session stopRunning];
    }

    _frameProcessingBlock = nil;

    if (_destinationImageBuffer.data) {
        free(_destinationImageBuffer.data);
        _destinationImageBuffer.data = nil;
    }
}

- (UInt16)brightness {
    return [self getValueForControl:UVCBrightness];
}

- (void)setBrightness:(UInt16)brightness {
    [self setValue:brightness forControl:UVCBrightness];
}

- (void)resetBrightness {
    [self setValue:self.defaultBrightness forControl:UVCBrightness];
}

- (UInt16)contrast {
    return [self getValueForControl:UVCContrast];
}

- (void)setContrast:(UInt16)contrast {
    [self setValue:contrast forControl:UVCContrast];
}

- (void)resetContrast {
    [self setValue:self.defaultContrast forControl:UVCContrast];
}

- (UInt16)hue {
    return [self getValueForControl:UVCHue];
}

- (void)setHue:(UInt16)hue {
    [self setValue:hue forControl:UVCHue];
}

- (void)resetHue {
    [self setValue:self.defaultHue forControl:UVCHue];
}

- (UInt16)saturation {
    return [self getValueForControl:UVCSaturation];
}

- (void)setSaturation:(UInt16)saturation {
    [self setValue:saturation forControl:UVCSaturation];
}

- (void)resetSaturation {
    [self setValue:self.defaultSaturation forControl:UVCSaturation];
}

- (UInt16)sharpness {
    return [self getValueForControl:UVCSharpness];
}

- (void)setSharpness:(UInt16)sharpness {
    [self setValue:sharpness forControl:UVCSharpness];
}

- (void)resetSharpness {
    [self setValue:self.defaultSharpness forControl:UVCSharpness];
}

- (UInt16)whiteBalanceTemperature {
    return [self getValueForControl:UVCWhiteBalanceTemperature];
}

- (void)setWhiteBalanceTemperature:(UInt16)whiteBalanceTemperature {
    self.autoWhiteBalanceTemperature = NO;
    [self setValue:whiteBalanceTemperature forControl:UVCWhiteBalanceTemperature];
}

- (void)resetWhiteBalanceTemperature {
    self.autoWhiteBalanceTemperature = NO;
    [self setValue:self.defaultWhiteBalanceTemperature forControl:UVCWhiteBalanceTemperature];
}

- (BOOL)autoWhiteBalanceTemperature {
    return [self getValueForControl:UVCAutoWhiteBalanceTemperature];
}

- (void)setAutoWhiteBalanceTemperature:(BOOL)autoWhiteBalanceTemperature {
    [self setValue:autoWhiteBalanceTemperature forControl:UVCAutoWhiteBalanceTemperature];
}

- (void)resetAutoWhiteBalanceTemperature {
    [self setValue:self.defaultAutoWhiteBalanceTemperature forControl:UVCAutoWhiteBalanceTemperature];
}

- (void)turnOnLED {
    [self setGPIO:GPIONumberLED direction:GPIODirectionOut];
    [self setGPIO:GPIONumberLED value:1];
}

- (void)turnOffLED {
    [self setGPIO:GPIONumberLED direction:GPIODirectionOut];
    [self setGPIO:GPIONumberLED value:0];
}

- (void)toggleLED {
    if (self.isLEDOn) {
        [self turnOffLED];
    }
    else {
        [self turnOnLED];
    }
}

- (BOOL)isLEDOn {
    [self setGPIO:GPIONumberLED direction:GPIODirectionIn];
    uint8_t uint8Value = [self getGPIOValue:GPIONumberLED];
    [self setGPIO:GPIONumberLED direction:GPIODirectionOut];

    return uint8Value != 0;
}

- (NSString* _Nonnull)deviceID {
    if (!_deviceID) {
        @throw [NSException exceptionWithName:@"ZEDCameraRuntimeError" reason:@"Attempted to read deviceID on non-open ZedVideoCapture" userInfo:nil];
    }

    return _deviceID;
}

- (NSString* _Nonnull)deviceName {
    if (!_deviceName) {
        @throw [NSException exceptionWithName:@"ZEDCameraRuntimeError" reason:@"Attempted to read deviceName on non-open ZedVideoCapture" userInfo:nil];
    }

    return _deviceName;
}

- (NSString* _Nonnull)deviceSerialNumber {
    if (!_usbDevice) {
        @throw [NSException exceptionWithName:@"ZEDCameraRuntimeError" reason:@"Attempted to read deviceSerialNumber on non-open ZedVideoCapture" userInfo:nil];
    }

    const int maxSerialNumberLengthInBytes = 6;
    const int serialNumberStartAddress = 0x18000;

    uint8_t data[maxSerialNumberLengthInBytes] = {0};

    [self getFlashProgramDataAtIndex:serialNumberStartAddress length:maxSerialNumberLengthInBytes output:data];

    if (data[0] != 'O' || data[1] != 'V') {
        @throw [NSException exceptionWithName:@"ZEDCameraRuntimeError" reason:@"Failed to read serial number" userInfo:nil];
    }

    int intValue = (data[2] << 24) + (data[3] << 16) + (data[4] << 8) + data[5];

    return [NSString stringWithFormat:@"%x", intValue];
}

#pragma mark - Private

- (UInt16)getValueForControl:(UInt16)control {
    IOReturn result = (*_uvcInterface)->USBInterfaceOpen(_uvcInterface);

    if (result != kIOReturnSuccess && result != kIOReturnExclusiveAccess) {
        @throw [NSException exceptionWithName:@"ZEDCameraRuntimeError" reason:@"Failed to open USB interface for get control value request" userInfo:nil];
    }

    UInt16 data = 0;

    IOUSBDevRequest controlRequest = {.bmRequestType = UVCRequestTypeIn,
        .bRequest = UVCRequestGetCurrent,
        .wValue = UInt16(control << 8),
        .wIndex = kUVCUnitID << 8,
        .wLength = kUVCControlValueSizeInBytes,
        .pData = &data};

    result = (*_uvcInterface)->ControlRequest(_uvcInterface, 0, &controlRequest);

    if (result != kIOReturnSuccess) {
        @throw [NSException exceptionWithName:@"ZEDCameraRuntimeError" reason:@"Failed to send UVC get value request" userInfo:nil];
    }

    (*_uvcInterface)->USBInterfaceClose(_uvcInterface);

    return data;
}

- (void)setValue:(UInt16)value forControl:(UInt16)control {
    IOReturn result = (*_uvcInterface)->USBInterfaceOpen(_uvcInterface);

    if (result != kIOReturnSuccess && result != kIOReturnExclusiveAccess) {
        @throw [NSException exceptionWithName:@"ZEDCameraRuntimeError" reason:@"Failed to open USB interface for set control value request" userInfo:nil];
    }

    IOUSBDevRequest controlRequest = {.bmRequestType = UVCRequestTypeOut,
        .bRequest = UVCRequestSetCurrent,
        .wValue = UInt16(control << 8),
        .wIndex = kUVCUnitID << 8,
        .wLength = kUVCControlValueSizeInBytes,
        .pData = &value};

    result = (*_uvcInterface)->ControlRequest(_uvcInterface, 0, &controlRequest);

    if (result != kIOReturnSuccess) {
        @throw [NSException exceptionWithName:@"ZEDCameraRuntimeError" reason:@"Failed to send UVC set value request" userInfo:nil];
    }

    (*_uvcInterface)->USBInterfaceClose(_uvcInterface);
}

- (void)setGPIO:(GPIONumber)gpioNumber direction:(GPIODirection)direction {
    UInt8 data[kXUBufferSizeInBytes] = {0x50, 0x10, gpioNumber, direction};
    [self sendXURequest:XUWriteRequest data:data];
}

- (void)setGPIO:(GPIONumber)gpioNumber value:(UInt8)value {
    UInt8 data[kXUBufferSizeInBytes] = {0x50, 0x12, gpioNumber, value};
    [self sendXURequest:XUWriteRequest data:data];
}

- (UInt8)getGPIOValue:(GPIONumber)gpioNumber {
    UInt8 data[kXUBufferSizeInBytes] = {0x51, 0x13, gpioNumber};
    [self sendXURequest:XUReadRequest data:data];

    return data[17];
}

- (void)getFlashProgramDataAtIndex:(int)index length:(int)length output:(UInt8*)output {
    uint8_t data[kXUBufferSizeInBytes] = {0x51, 0xa1, 0x03};
    data[5] = (index >> 24) & 0xff;
    data[6] = (index >> 16) & 0xff;
    data[7] = (index >> 8) & 0xff;
    data[8] = index & 0xff;

    int packVal = 36864 + length;
    data[9] = (packVal >> 8) & 0xff;
    data[10] = packVal & 0xff;
    data[11] = (length >> 8) & 0xff;
    data[12] = length & 0xff;

    [self sendXURequest:XUReadRequest data:data];

    memcpy(output, &data[17], length);
}

- (void)sendXURequest:(XURequest)xuRequest data:(UInt8*)data {
    IOCFPlugInInterface** plugInInterface = nil;
    SInt32 score;
    kern_return_t kernelResult = IOCreatePlugInInterfaceForService(_usbDevice, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &plugInInterface, &score);

    if ((kernelResult != kIOReturnSuccess) || !plugInInterface) {
        @throw [NSException exceptionWithName:@"ZEDCameraRuntimeError" reason:@"Failed to create USB plugin interface for extension unit request" userInfo:nil];
    }

    IOUSBDeviceInterface300** deviceInterface = nil;
    IOReturn ioResult = (*plugInInterface)->QueryInterface(plugInInterface, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID), (LPVOID*)&deviceInterface);
    IODestroyPlugInInterface(plugInInterface);

    if ((ioResult != 0) || !deviceInterface) {
        @throw [NSException exceptionWithName:@"ZEDCameraRuntimeError" reason:@"Failed to find USB interface for extension unit request" userInfo:nil];
    }

    IOReturn result = (*deviceInterface)->USBDeviceOpen(deviceInterface);

    if (result != kIOReturnSuccess && result != kIOReturnExclusiveAccess) {
        @throw [NSException exceptionWithName:@"ZEDCameraRuntimeError" reason:@"Failed to open USB interface for extension unit request" userInfo:nil];
    }

    IOUSBDevRequest setTaskRequest = {.bmRequestType = XURequestTypeOut,
        .bRequest = UVCRequestSetCurrent,
        .wValue = kXUControlSelector << 8,
        .wIndex = kXUID << 8,
        .wLength = kXUBufferSizeInBytes,
        .pData = data};

    result = (*deviceInterface)->DeviceRequest(deviceInterface, &setTaskRequest);

    if (result != kIOReturnSuccess) {
        @throw [NSException exceptionWithName:@"ZEDCameraRuntimeError" reason:@"Failed to send extension unit set task request" userInfo:nil];
    }

    if (xuRequest == XUReadRequest) {
        IOUSBDevRequest getDataRequest = {.bmRequestType = XURequestTypeIn,
            .bRequest = UVCRequestGetCurrent,
            .wValue = kXUControlSelector << 8,
            .wIndex = kXUID << 8,
            .wLength = kXUBufferSizeInBytes,
            .pData = data};

        result = (*deviceInterface)->DeviceRequest(deviceInterface, &getDataRequest);

        if (result != kIOReturnSuccess) {
            @throw [NSException exceptionWithName:@"ZEDCameraRuntimeError" reason:@"Failed to send extension unit get data request" userInfo:nil];
        }
    }

    (*deviceInterface)->USBDeviceClose(deviceInterface);
    (*deviceInterface)->Release(deviceInterface);
}

- (void)reset {
    _frameProcessingBlock = nil;
    _desiredFrameDuration = kCMTimeInvalid;
    _desiredFormat = nil;
    _device = nil;
    _session = nil;

    if (_uvcInterface) {
        (*_uvcInterface)->Release(_uvcInterface);
    }

    _uvcInterface = nil;

    if (_usbDevice) {
        IOObjectRelease(_usbDevice);
    }

    _usbDevice = 0;

    if (_destinationImageBuffer.data) {
        free(_destinationImageBuffer.data);
        _destinationImageBuffer.data = nil;
    }

    _deviceID = nil;
    _deviceName = nil;
}

- (void)dealloc {
    [self reset];
    [super dealloc];
}

@end

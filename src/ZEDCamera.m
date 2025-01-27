//
// ZEDCamera.m
// zed-open-capture-mac
//
// Created by Christian Bator on 01/27/2025
//

#import <Foundation/Foundation.h>
#include <IOKit/IOCFPlugIn.h>
#import <IOKit/IOKitLib.h>
#include <IOKit/usb/IOUSBLib.h>
#include "ZEDCamera.h"

//
// UVC Request Codes
//
#define kUVCSetCurrent 0x01
#define kUVCGetCurrent 0x81

#define kZEDBrightness 2
#define kZEDSharpness 8
#define kZEDContrast 3
#define kZEDHue 6
#define kZEDSaturation 7
#define kZEDGamma 9
#define kZEDGain 4

//
// ZEDCamera
//
@interface ZEDCamera ()

@property (nonatomic, assign) IOUSBInterfaceInterface220** controllerInterface;
@property (nonatomic, assign) UInt16 uvcVersion;
@property (nonatomic, assign) UInt8 videoInterfaceIndex;

@end

@implementation ZEDCamera

#pragma mark - Initialization

- (_Nullable instancetype)initWithService:(io_service_t)service {
    [super init];

    IOUSBDeviceInterface** deviceInterface = NULL;
    IOCFPlugInInterface** plugInInterface = NULL;

    SInt32 score;
    kern_return_t krc = IOCreatePlugInInterfaceForService(service, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &plugInInterface, &score);

    if ((krc != kIOReturnSuccess) || !plugInInterface) {
        return nil;
    }

    IOReturn hrc = (*plugInInterface)->QueryInterface(plugInInterface, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID), (LPVOID*)&deviceInterface);

    IODestroyPlugInInterface(plugInInterface);
    if ((hrc != 0) || !deviceInterface) {
        return nil;
    }

    io_iterator_t interfaceIter;
    IOUSBFindInterfaceRequest interfaceRequest = {.bInterfaceClass = kUSBVideoInterfaceClass,
        .bInterfaceSubClass = kUSBVideoControlSubClass,
        .bInterfaceProtocol = kIOUSBFindInterfaceDontCare,
        .bAlternateSetting = kIOUSBFindInterfaceDontCare};

    hrc = (*deviceInterface)->CreateInterfaceIterator(deviceInterface, &interfaceRequest, &interfaceIter);
    (*deviceInterface)->Release(deviceInterface);

    if ((hrc != 0) || !interfaceIter) {
        return nil;
    }

    io_service_t usbInterface = IOIteratorNext(interfaceIter);

    IOObjectRelease(interfaceIter);
    if (!usbInterface) {
        return nil;
    }

    krc = IOCreatePlugInInterfaceForService(usbInterface, kIOUSBInterfaceUserClientTypeID, kIOCFPlugInInterfaceID, &plugInInterface, &score);
    IOObjectRelease(usbInterface);
    if ((krc != kIOReturnSuccess) || !plugInInterface) {
        return nil;
    }

    hrc = (*plugInInterface)->QueryInterface(plugInInterface, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID), (LPVOID*)&_controllerInterface);
    IODestroyPlugInInterface(plugInInterface);
    if ((hrc != 0) || !_controllerInterface) {
        return nil;
    }

    hrc = (*_controllerInterface)->GetInterfaceNumber(_controllerInterface, &_videoInterfaceIndex);

    if (hrc != 0) {
        return nil;
    }

    io_name_t nameBuffer;
    if (IORegistryEntryGetName(service, nameBuffer) == KERN_SUCCESS) {
        _deviceName = [NSString stringWithUTF8String:nameBuffer];
    }

    CFNumberRef vendorIdObj = IORegistryEntrySearchCFProperty(service, kIOUSBPlane, CFSTR(kUSBVendorID), kCFAllocatorDefault, 0);
    CFNumberRef productIdObj = IORegistryEntrySearchCFProperty(service, kIOUSBPlane, CFSTR(kUSBProductID), kCFAllocatorDefault, 0);
    CFNumberRef locationIdObj = IORegistryEntrySearchCFProperty(service, kIOUSBPlane, CFSTR(kUSBDevicePropertyLocationID), kCFAllocatorDefault, 0);

    UInt32 locationId = 0;
    UInt16 vendorId = 0;
    UInt16 productId = 0;

    if (vendorIdObj) {
        CFNumberGetValue(vendorIdObj, kCFNumberSInt16Type, &vendorId);
        CFRelease(vendorIdObj);
    }

    if (productIdObj) {
        CFNumberGetValue(productIdObj, kCFNumberSInt16Type, &productId);
        CFRelease(productIdObj);
    }

    if (locationIdObj) {
        CFNumberGetValue(locationIdObj, kCFNumberSInt32Type, &locationId);
        CFRelease(locationIdObj);
    }

    _locationId = locationId;
    _vendorId = vendorId;
    _productId = productId;

    IOObjectRetain(service);

    return self;
}

+ (_Nullable instancetype)first {
    return [[ZEDCamera all] firstObject];
}

+ (NSArray<ZEDCamera*>* _Nonnull)all {
    NSMutableArray* cameras = [[NSMutableArray alloc] init];
    io_iterator_t serviceIterator;

    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(kIOUSBDeviceClassName), &serviceIterator) == KERN_SUCCESS) {
        io_service_t service;

        while ((service = IOIteratorNext(serviceIterator))) {
            ZEDCamera* camera = [[ZEDCamera alloc] initWithService:service];
            IOObjectRelease(service);

            if (camera) {
                [cameras addObject:camera];
            }
        }

        IOObjectRelease(serviceIterator);
    }

    // TODO: Sort the cameras by location, name, or something else

    return cameras;
}

#pragma mark - Public Interface

- (UInt16)brightness {
    return [self getCurrentValueWithCode:kZEDBrightness];
}

- (UInt16)sharpness {
    return [self getCurrentValueWithCode:kZEDSharpness];
}

- (UInt16)contrast {
    return [self getCurrentValueWithCode:kZEDContrast];
}

- (UInt16)hue {
    return [self getCurrentValueWithCode:kZEDHue];
}

- (UInt16)saturation {
    return [self getCurrentValueWithCode:kZEDSaturation];
}

- (UInt16)gamma {
    return [self getCurrentValueWithCode:kZEDGamma];
}

- (UInt16)gain {
    return [self getCurrentValueWithCode:kZEDGain];
}

#pragma mark - Private Utilities

- (UInt16)getCurrentValueWithCode:(UInt16)valueCode {
    IOReturn result = (*_controllerInterface)->USBInterfaceOpen(_controllerInterface);

    if (result != kIOReturnSuccess && result != kIOReturnExclusiveAccess) {
        @throw [NSException exceptionWithName:@"ZEDCameraRuntimeError"
                                       reason:@"Failed to open USB interface"
                                     userInfo:nil];
    }

    UInt16 data = 0;
    UInt16 index = 3; // TODO: don't hardcode this

    IOUSBDevRequest controlRequest = {
        .bmRequestType = USBmakebmRequestType(kUSBIn, kUSBClass, kUSBInterface),
        .bRequest = kUVCGetCurrent,
        .wValue = (valueCode << 8),
        .wIndex = (index << 8) | _videoInterfaceIndex,
        .wLength = 2, // UInt16 values
        .wLenDone = 0,
        .pData = &data
    };

    result = (*_controllerInterface)->ControlRequest(_controllerInterface, 0, &controlRequest);

    if (result != kIOReturnSuccess) {
        @throw [NSException exceptionWithName:@"ZEDCameraRuntimeError"
                                       reason:@"Failed to send USB request"
                                     userInfo:nil];
    }

    (*_controllerInterface)->USBInterfaceClose(_controllerInterface);

    return data;
}

- (void)logInfo {
    printf("%-14s %-12s %-12s %s\n", "Vend:Prod", "LocationID", "UVC Version", "Device name");
    printf("-------------- ------------ ------------ ------------------------------------------------\n");

    char versionStr[8];
    snprintf(versionStr, sizeof(versionStr), "%d.%02x", (short)(_uvcVersion >> 8), (_uvcVersion & 0xFF));

    printf(
        "0x%04x:0x%04x  0x%08x   %-5s        %s\n", _vendorId, _productId, _locationId, versionStr, [_deviceName cStringUsingEncoding:NSASCIIStringEncoding]);

    printf("-------------- ------------ ------------ ------------------------------------------------\n");
}

@end

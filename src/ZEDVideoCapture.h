//
// ZEDVideoCapture.h
// zed-open-capture-mac
//
// Created by Christian Bator on 01/11/2025
//

#include "../include/zed_video_capture_format.h"
#include <Foundation/Foundation.h>

@interface ZEDVideoCapture : NSObject

- (_Nonnull instancetype)init;

@property (nonatomic, strong, nonnull) NSString* deviceID;
@property (nonatomic, strong, nonnull) NSString* deviceName;
@property (nonatomic, strong, nonnull) NSString* deviceSerialNumber;

@property (nonatomic) UInt16 brightness;
@property (nonatomic) UInt16 contrast;
@property (nonatomic) UInt16 hue;
@property (nonatomic) UInt16 saturation;
@property (nonatomic) UInt16 sharpness;
@property (nonatomic) UInt16 whiteBalanceTemperature;
@property (nonatomic) BOOL autoWhiteBalanceTemperature;

@property (nonatomic, readonly) UInt16 defaultBrightness;
@property (nonatomic, readonly) UInt16 defaultContrast;
@property (nonatomic, readonly) UInt16 defaultHue;
@property (nonatomic, readonly) UInt16 defaultSaturation;
@property (nonatomic, readonly) UInt16 defaultSharpness;
@property (nonatomic, readonly) UInt16 defaultWhiteBalanceTemperature;
@property (nonatomic, readonly) BOOL defaultAutoWhiteBalanceTemperature;

- (void)resetBrightness;
- (void)resetContrast;
- (void)resetHue;
- (void)resetSaturation;
- (void)resetSharpness;
- (void)resetWhiteBalanceTemperature;
- (void)resetAutoWhiteBalanceTemperature;

@property (nonatomic, readonly) BOOL isLEDOn;
- (void)turnOnLED;
- (void)turnOffLED;
- (void)toggleLED;

- (BOOL)openWithResolution:(zed::Resolution)resolution frameRate:(zed::FrameRate)frameRate colorSpace:(zed::ColorSpace)colorSpace;
- (void)close;

- (void)start:(void (^_Nonnull)(uint8_t* _Nonnull, size_t, size_t, size_t))frameProcessingBlock;
- (void)stop;

@end

//
// ZEDCamera.h
// zed-open-capture-mac
//
// Created by Christian Bator on 01/27/2025
//

#include <Foundation/Foundation.h>

@interface ZEDCamera : NSObject

@property (nonatomic, strong, nullable) NSString* deviceName;
@property (nonatomic, assign) UInt32 locationId;
@property (nonatomic, assign) UInt16 vendorId;
@property (nonatomic, assign) UInt16 productId;

@property (nonatomic, assign) UInt16 brightness;
@property (nonatomic, assign) UInt16 sharpness;
@property (nonatomic, assign) UInt16 contrast;
@property (nonatomic, assign) UInt16 hue;
@property (nonatomic, assign) UInt16 saturation;
@property (nonatomic, assign) UInt16 gamma;
@property (nonatomic, assign) UInt16 gain;

// TODO: White Balance

// TODO: LED

+ (_Nullable instancetype)first;
+ (NSArray<ZEDCamera*>* _Nonnull)all;

- (void)logInfo;

@end

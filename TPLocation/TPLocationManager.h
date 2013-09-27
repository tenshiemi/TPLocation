//
//  TPLocationManager.h
//  TPLocation
//
//  Created by Jen on 9/6/13.
//  Copyright (c) 2013 Tetherpad, Inc. All rights reserved.
//


#import <CoreLocation/CoreLocation.h>
#import <Foundation/Foundation.h>

NSString *NSStringFromCLLocationCoordinate2D(CLLocationCoordinate2D coordinate);

@interface TPLocationManager : NSObject <CLLocationManagerDelegate>

@property (nonatomic) BOOL enabled;
@property (nonatomic) NSTimeInterval timeout;

typedef void (^TPLocationManagerCompletionHandler)(CLLocation *location, NSError *error);

+ (TPLocationManager *)sharedManager;
- (void)loadLocationWithHandler:(TPLocationManagerCompletionHandler)handler;

@end

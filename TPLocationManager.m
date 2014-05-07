//
//  TPLocationManager.m
//  TPLocation
//
//  Created by Jen on 9/6/13.
//  Copyright (c) 2013 Tetherpad, Inc. All rights reserved.
//

#import "TPLocationManager.h"

static const NSTimeInterval kDesiredFreshnessForeground = 180.0; // seconds
static const NSTimeInterval kDesiredFreshnessBackground = 600.0; // seconds
static const CLLocationDistance kLNDistanceFilterForeground = 20.0; // meters
static const NSTimeInterval kDefaultTimeout = 10.0; // seconds
static const NSInteger kLNTimeoutErrorCode = 100; // NSError code
static NSString *kErrorDomain = @"TPLocationErrorDomain";

NSString *NSStringFromCLLocationCoordinate2D(CLLocationCoordinate2D coordinate) {
    return [NSString stringWithFormat:@"%f,%f", coordinate.latitude, coordinate.longitude];
}

@interface TPLocationManager ()

@property (nonatomic, readonly) CLLocationManager *locationManager;
@property (strong, nonatomic) CLLocation *lastLocation;
@property (weak, nonatomic) NSTimer *locationTimeoutTimer;
@property (nonatomic, readonly) dispatch_queue_t handlersQueue;
@property (strong, nonatomic) NSMutableSet *handlers;
@property (nonatomic) BOOL updatingLocation;
@property (nonatomic, strong) id appDidEnterBackgroundObserver;
@property (nonatomic, strong) id appDidBecomeActiveObserver;

@end

@implementation TPLocationManager

@synthesize locationManager = _locationManager;
@synthesize handlersQueue = _handlersQueue;
@synthesize timeout = _timeout;

+ (TPLocationManager *)sharedManager {
    static TPLocationManager *sharedManager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [self new];
    });
    return sharedManager;
}

- (dispatch_queue_t)handlersQueue {
    if (! _handlersQueue) {
        _handlersQueue = dispatch_queue_create("com.tetherpad.TPLocationManager", DISPATCH_QUEUE_SERIAL);
    }
    return _handlersQueue;
}

- (NSMutableSet *)handlers {
    if (! _handlers) {
        _handlers = [NSMutableSet set];
    }
    return _handlers;
}

- (NSTimeInterval)timeout {
    if (!_timeout) {
        _timeout = kDefaultTimeout;
    }
    return _timeout;
}

- (void)setTimeout:(NSTimeInterval)timeout {
    _timeout = timeout;
}

- (void)setEnabled:(BOOL)enabled {
    if (enabled && [self isAuthorized]) {
        // Use significant location changes and request GPS location only if
        // necessary.
        [self startUpdatingLocation];
        [self.locationManager startMonitoringSignificantLocationChanges];
        // Get latest location when application becomes active
        self.appDidBecomeActiveObserver = [[NSNotificationCenter defaultCenter]
                                           addObserverForName:UIApplicationDidBecomeActiveNotification
                                           object:[UIApplication sharedApplication]
                                           queue:[NSOperationQueue mainQueue]
                                           usingBlock:^(NSNotification *note) {
                                               [self startUpdatingLocation];
                                           }];
        // Stop any in-progress location fetches if application enters background
        self.appDidEnterBackgroundObserver = [[NSNotificationCenter defaultCenter]
                                              addObserverForName:UIApplicationDidEnterBackgroundNotification
                                              object:[UIApplication sharedApplication]
                                              queue:[NSOperationQueue mainQueue]
                                              usingBlock:^(NSNotification *note) {
                                                  [self stopUpdatingLocation];
                                              }];
    } else {
        [self stopUpdatingLocation];
        [self.locationManager stopMonitoringSignificantLocationChanges];
        [[NSNotificationCenter defaultCenter] removeObserver:self.appDidBecomeActiveObserver];
        [[NSNotificationCenter defaultCenter] removeObserver:self.appDidEnterBackgroundObserver];
    }
    
    _enabled = enabled;
}

#pragma mark NSObject

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    self.locationManager.delegate = nil;
    [self cancelLocationTimeoutTimer];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSAssert([NSThread isMainThread], @"must init on main thread");
        // Setup the CLLocationManager here so that we ensure it's allocated
        // on the main thread.
        _locationManager = [[CLLocationManager alloc] init];
        _locationManager.delegate = self;
        _locationManager.distanceFilter = kLNDistanceFilterForeground;
        _locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters;
    }
    return self;
}

#pragma mark Start/Stop

- (void)startUpdatingLocation {
    if (self.enabled && !self.updatingLocation) {
        if ([CLLocationManager authorizationStatus] == kCLAuthorizationStatusAuthorized) {
            self.updatingLocation = YES;
            [self startLocationTimeoutTimer];
            dispatch_async(dispatch_get_main_queue(), ^{  // Must run CLLocationManager on main thread
                [self.locationManager startUpdatingLocation];
            });
        } else {
            NSLog(@"Not starting location updates because we are not authorized.");
        }
    } else {
        NSLog(@"Not starting. enabled: %@, updatingLocation: %@",   self.enabled ? @"YES" : @"NO",
                                                                    self.updatingLocation ? @"YES" : @"NO");
    }
}

- (void)stopUpdatingLocation {
    [self.locationManager stopUpdatingLocation];
    self.updatingLocation = NO;
    [self cancelLocationTimeoutTimer];
}

- (void)locationTimeoutTimerDidFire {
    [self stopUpdatingLocation];
    NSString *description = [NSString stringWithFormat:@"Location update operation timed out after %f seconds.", self.timeout];
    NSError *error = [NSError errorWithDomain:kErrorDomain
                                         code:kLNTimeoutErrorCode
                                     userInfo:@{NSLocalizedDescriptionKey:description}];
    [self locationManager:self.locationManager didFailWithError:error];
}

#pragma mark CLLocationManagerDelegate methods

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    if ([locations count] == 0) {
        return;
    }
    CLLocation *newLocation = [locations lastObject];
    
    // Verify that location is recent enough to be useful
    if (! [self isLocationFresh:newLocation]) {
        return;
    }
    // Verify that this reading is valid
    if (newLocation.horizontalAccuracy < 0) {
        return;
    }

    // We have a winner:
    NSLog(@"Got location.");
    self.lastLocation = newLocation;
    [self stopUpdatingLocation];
    
    // Run handlers
    __block NSSet *s = nil;
    // Use dispatch_async on the handlersQueue to eliminate race conditions
    dispatch_async(self.handlersQueue, ^{
        s = [self.handlers copy];
        [self.handlers removeAllObjects];
        for (TPLocationManagerCompletionHandler handler in s) {
            // Run handlers on main queue
            dispatch_async(dispatch_get_main_queue(), ^{
                handler(newLocation, nil);
            });
        }
    });
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    NSLog(@"error: %@", error);
    __block NSSet *s = nil;
    // Use dispatch_async on the handlersQueue to eliminate race conditions
    dispatch_async(self.handlersQueue, ^{
        s = [self.handlers copy];
        [self.handlers removeAllObjects];
        for (TPLocationManagerCompletionHandler handler in s) {
            // Run handlers on the main queue
            dispatch_async(dispatch_get_main_queue(), ^{
                handler(nil, error);
            });
        }
    });
}

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    if (status == kCLAuthorizationStatusAuthorized) {
        if (self.enabled) {
            [self.locationManager startMonitoringSignificantLocationChanges];
        }
    } else {
        [self.locationManager stopMonitoringSignificantLocationChanges];
        [self stopUpdatingLocation];
    }
}

#pragma mark Authorization

- (BOOL)isAuthorized {
    return ([CLLocationManager authorizationStatus] == kCLAuthorizationStatusAuthorized);
}

#pragma mark Location Freshness

- (BOOL)isLocationFresh:(CLLocation *)location {
    NSTimeInterval locationAge = ABS([location.timestamp timeIntervalSinceNow]);
    BOOL inBackground = ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground);
    
    // Verify that location is recent enough to be useful
    if (inBackground) {
        if (locationAge < kDesiredFreshnessBackground) {
            return YES;
        }
    } else {
        if (locationAge < kDesiredFreshnessForeground) {
            return YES;
        }
    }
    return NO;
}

#pragma mark NSTimer

- (void)startLocationTimeoutTimer {
    [self cancelLocationTimeoutTimer];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.locationTimeoutTimer = [NSTimer scheduledTimerWithTimeInterval:self.timeout
                                                                     target:self
                                                                   selector:@selector(locationTimeoutTimerDidFire)
                                                                   userInfo:nil
                                                                    repeats:NO];
    });
}

- (void)cancelLocationTimeoutTimer {
    if (self.locationTimeoutTimer) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.locationTimeoutTimer invalidate];
            self.locationTimeoutTimer= nil;
        });
    }
}

#pragma mark Public Interface

- (void)loadLocationWithHandler:(TPLocationManagerCompletionHandler)handler {
    if (self.lastLocation && [self isLocationFresh:self.lastLocation]) {
        handler(self.lastLocation, nil);
    } else {
        dispatch_async(self.handlersQueue, ^{
            [self.handlers addObject:handler];
        });
        [self startUpdatingLocation];
    }
}

@end

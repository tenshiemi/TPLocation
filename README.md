# TPLocation

A library to turn the CLLocationManager delegate interface into a simple asynchronous method with completion block.

## Usage

    // In your AppDelegate.m

    #import <TPLocation/TPLocationManager.h>
    [TPLocationManager sharedManager].enabled = YES;

    // Wherever you need a location 

    [[TPLocationManager sharedManager] loadLocationWithHandler:^(CLLocation *location, NSError *error) {
        if (error) {
            ...
        } else {
            ...
        }
    }];

## Installation

Easiest way: use Cocoapods. Otherwise, copy the .h and .m into your project.

    $ edit Podfile
    platform :ios, '6.1'
    pod 'TPLocation', '~> 1.0.0'
    
    $ pod install
    
    $ open App.xcworkspace
    
## Motivation

This library provides location data for your app, filtered for freshness and accuracy.

Since it's a single shared object for your app, you can simply import the header file and ask for a location fix anywhere you need location data in your app. 

Designed to be low-power and lightweight, this library turns on active location monitoring only when absolutely necessary, and relies on significant location changes when possible. Location updates are turned off as soon as a viable location fix has been established.

Since an app may have more than one asynchronously executing thread which requires location data, TPLocation collects overlapping requests, and calls all outstanding completion blocks when location data is received. Handlers are managed via a serial queue, preventing race conditions.  

TPLocation ensures that location requests are run on the main queue, as required by the CLLocationManager specification. TPLocation runs completion handlers on the main queue as well.

A timeout parameter in the interface allows users to configure how long they wish to wait for a location fix. If a timeout occurs, the completion block will be given an error indicating that this is the case.

## License

TPLocation is available under the MIT license. See the LICENSE file for more info.

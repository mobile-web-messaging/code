//
//  MWMViewController.m
//  Motions
//
//  Created by Jeff Mesnil on 14/03/2014.
//  Copyright (c) 2014 Mobile & Web Messaging. All rights reserved.
//

#import "MWMViewController.h"
#import <CoreMotion/CoreMotion.h>
#import <MQTTKit/MQTTKit.h>

#define kMqttHost @"iot.eclipse.org"
#define kAlertTopic @"/mwm/%@/alert"

@interface MWMViewController ()

@property (weak, nonatomic) IBOutlet UILabel *deviceIDLabel;
@property (weak, nonatomic) IBOutlet UILabel *pitchLabel;
@property (weak, nonatomic) IBOutlet UILabel *rollLabel;
@property (weak, nonatomic) IBOutlet UILabel *yawLabel;

@property (strong, nonatomic) NSString *deviceID;

@property (strong, nonatomic) CMMotionManager *motionManager;
@property (strong, nonatomic) MQTTClient *client;
@end

@implementation MWMViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.deviceID = [UIDevice currentDevice].identifierForVendor.UUIDString;
    self.deviceID = @"C0962483-7DD9-43CC-B1A0-2E7FBFC05060";
    NSLog(@"Device identifier is %@", self.deviceID);
    self.deviceIDLabel.text = self.deviceID;

    self.motionManager = [[CMMotionManager alloc] init];
    // get the device motion updates every second.
    self.motionManager.deviceMotionUpdateInterval = 1;
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    [self.motionManager startDeviceMotionUpdatesToQueue:queue
                                            withHandler:^(CMDeviceMotion *motion, NSError *error) {
        if(!error) {
            CMAttitude *attitude = motion.attitude;
            dispatch_async(dispatch_get_main_queue(), ^{
                // convert values from radians to degrees
                double pitch = attitude.pitch * 180 / M_PI;
                double roll = attitude.roll * 180 / M_PI;
                double yaw = attitude.yaw * 180 / M_PI;
                self.pitchLabel.text = [NSString stringWithFormat:@"pitch: %.0f°", pitch];
                self.rollLabel.text = [NSString stringWithFormat:@"roll: %.0f°", roll];
                self.yawLabel.text = [NSString stringWithFormat:@"yaw: %.0f°", yaw];
            });
            [self send:attitude];
        }
    }];
    
    self.client = [[MQTTClient alloc] initWithClientId:self.deviceID];

    // use a weak reference to avoid a retain/release cycle in the block
    __weak MWMViewController *weakSelf = self;
    self.client.messageHandler = ^(MQTTMessage *message) {
        NSString *alertTopic = [NSString stringWithFormat:kAlertTopic, weakSelf.deviceID];
        if ([alertTopic isEqualToString:message.topic]) {
            NSString *color = message.payloadString;
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf warnUser:color];
            });
        }
    };
    
    [self connect];
}

- (void)dealloc
{
    [self.motionManager stopDeviceMotionUpdates];
    [self unsubscribe];
    [self disconnect];
}

#pragma mark - MQTTKit Actions

- (void)connect
{
    NSLog(@"Connecting to %@...", kMqttHost);
    [self.client connectToHost:kMqttHost
             completionHandler:^(MQTTConnectionReturnCode code) {
        if (code == ConnectionAccepted) {
            NSLog(@"connected to the MQTT broker");
            [self subscribe];
        } else {
            NSLog(@"Failed to connect to the MQTT broker: code=%lu", (unsigned long)code);
        }
    }];
}

- (void)disconnect
{
    [self.client disconnectWithCompletionHandler:^(NSUInteger code) {
        if (code == 0) {
            NSLog(@"disconnected from the MQTT broker");
        } else {
            NSLog(@"disconnected unexpectedly...");
        }
    }];
}

- (void)setWill
{
    self.client.keepAlive = 5;
    self.client.disconnectionHandler = ^(NSUInteger code) {
        NSLog(@"unexpected disconnection %lu", (unsigned long)code);
    };

    NSString *willTopic = @"/mwm/lastWill";
    NSString *willMessage = [NSString stringWithFormat:@"Device %@ has unexpectedly died", self.deviceID];
    [self.client setWill:willMessage
                 toTopic:willTopic
                 withQos:ExactlyOnce
                  retain:NO];

    // connect after having set the client's last will
    [self.client connectToHost:kMqttHost
             completionHandler:^(MQTTConnectionReturnCode code) {
                 //...
             }];
}

- (void)send:(CMAttitude *)attitude
{
    uint64_t values[3] = {
        CFConvertDoubleHostToSwapped(attitude.pitch).v,
        CFConvertDoubleHostToSwapped(attitude.roll).v,
        CFConvertDoubleHostToSwapped(attitude.yaw).v
    };
    NSData *data = [NSData dataWithBytes:&values length:sizeof(values)];
    NSString *topic =[NSString stringWithFormat:@"/mwm/%@/motion", self.deviceID];
    [self.client publishData:data
                     toTopic:topic
                     withQos:AtMostOnce
                      retain:YES
           completionHandler:nil];
}

- (void)subscribe
{
    NSString *topic = [NSString stringWithFormat:kAlertTopic, self.deviceID];
    [self.client subscribe:topic withQos:AtLeastOnce completionHandler:^(NSArray *grantedQos) {
        NSLog(@"subscribed to %@ with QoS %@", topic, grantedQos);
    }];
}

- (void)unsubscribe
{
    NSString *topic = [NSString stringWithFormat:kAlertTopic, self.deviceID];
    [self.client unsubscribe:topic withCompletionHandler:nil];
}

# pragma mark - UI Actions

// Warn the user by changing the view's background color to the specified color during 2 seconds
- (void)warnUser:(NSString *)colorStr
{
    // keep a reference to the original color
    UIColor *originalColor = self.view.backgroundColor;
    
    [UIView animateWithDuration:0.5
                          delay:0.0
                        options:0
                     animations:^{
                         // change it to the color passed in parameter
                         SEL sel = NSSelectorFromString([NSString stringWithFormat:@"%@Color", colorStr]);
                         UIColor* color = nil;
                         if ([UIColor respondsToSelector:sel]) {
                             color  = [UIColor performSelector:sel];
                         } else {
                             color = [UIColor redColor];
                         }
                         self.view.backgroundColor = color;
                     }
                     completion:^(BOOL finished) {
                         // after a delay of 2 seconds, revert it to the original color
                         [UIView animateWithDuration:0.5
                                               delay:2
                                             options:0
                                          animations:^{
                                              self.view.backgroundColor = originalColor;
                                          }
                                          completion:nil];
                     }];
}

@end

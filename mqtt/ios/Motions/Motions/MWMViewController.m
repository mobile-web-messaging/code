//
//  MWMViewController.m
//  Motions
//
//  Created by Jeff Mesnil on 10/02/2014.
//  Copyright (c) 2014 Mobile & Web Messaging. All rights reserved.
//

#import "MWMViewController.h"
#import <MQTTKit/MQTTKit.h>
#import <CoreMotion/CoreMotion.h>

#define kMqttHost @"iot.eclipse.org"
#define kMotionTopic @"/MQTTMWM/Motions/%@"
#define kAlertTopic @"/MQTTMWM/Motions/%@/alerts"

@interface MWMViewController () <MQTTClientDelegate>

@property (weak, nonatomic) IBOutlet UILabel *deviceIDLabel;
@property (weak, nonatomic) IBOutlet UILabel *pitchLabel;
@property (weak, nonatomic) IBOutlet UILabel *rollLabel;
@property (weak, nonatomic) IBOutlet UILabel *yawLabel;

@property (strong, nonatomic) MQTTClient *mqttClient;
@property (strong, nonatomic) NSString *deviceID;

@property (strong, nonatomic) CMMotionManager *motionManager;

@end

@implementation MWMViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.deviceID = [UIDevice currentDevice].identifierForVendor.UUIDString;
    NSLog(@"Client identifier is %@", self.deviceID);
    self.deviceIDLabel.text = self.deviceID;
    
    self.motionManager = [[CMMotionManager alloc] init];
    // use a frequency of circa 10Hz to get the device motion updates
    self.motionManager.deviceMotionUpdateInterval = 0.1;
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    [self.motionManager startDeviceMotionUpdatesToQueue:queue withHandler:^(CMDeviceMotion *motion, NSError *error) {
        if(!error) {
            [self send:motion.attitude];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.pitchLabel.text = [NSString stringWithFormat:@"pitch: %.1f", motion.attitude.pitch];
                self.rollLabel.text = [NSString stringWithFormat:@"roll: %.1f", motion.attitude.roll];
                self.yawLabel.text = [NSString stringWithFormat:@"yaw: %.1f", motion.attitude.yaw];
            });
        }
    }];
    [self connect];
}

- (void)dealloc
{
    [self.motionManager stopDeviceMotionUpdates];
    [self unsubscribe];
    [self disconnect];
}

#pragma mark - MQTT actions

- (void)connect
{
    self.mqttClient = [[MQTTClient alloc] initWithClientId:self.deviceID];
    // Override point for customization after application launch.
    self.mqttClient.delegate = self;
    [self.mqttClient connectToHost:kMqttHost];
}

- (void)disconnect
{
    [self.mqttClient disconnect];
}

- (void)subscribe
{
    NSString *alertTopic = [NSString stringWithFormat:kAlertTopic, self.deviceID];
    [self.mqttClient subscribe:alertTopic
                       withQos:0];
}

- (void)unsubscribe
{
    NSString *alertTopic = [NSString stringWithFormat:kAlertTopic, self.deviceID];
    [self.mqttClient unsubscribe:alertTopic];
}

- (void)send:(CMAttitude *)attitude
{
    uint64_t values[3] = { CFConvertDoubleHostToSwapped(attitude.pitch).v,
        CFConvertDoubleHostToSwapped(attitude.roll).v,
        CFConvertDoubleHostToSwapped(attitude.yaw).v};
    NSData *data = [NSData dataWithBytes:&values length:sizeof(values)];
    [self.mqttClient publishData:data
                           toTopic:[NSString stringWithFormat:kMotionTopic, self.deviceID]
                           withQos:0
                            retain:NO];
}

#pragma mark - MQTTClientDelegate

- (void)client:(MQTTClient *)client
    didConnect:(NSUInteger)code
{
    // once connect, subscribe to the client's alerts topic
    [self subscribe];
}

- (void)client:(MQTTClient *)client didReceiveMessage:(MQTTMessage *)message
{
    NSString *alertTopic = [NSString stringWithFormat:kAlertTopic, self.deviceID];
    if ([alertTopic isEqualToString:message.topic]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self warnUser];
        });
    }
}

# pragma mark - UI Actions

// Warn the user by changing the view's background color to red for 2 seconds
- (void)warnUser
{
    // keep a reference to the original color
    UIColor *originalColor = self.view.backgroundColor;
    
    [UIView animateWithDuration:0.5
                          delay:0.0
                        options:0
                     animations:^{
                         // change it to red
                         self.view.backgroundColor = [UIColor redColor];
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
